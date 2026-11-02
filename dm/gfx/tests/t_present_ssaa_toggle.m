#import "../nvn/host_msl.h"
#include <string.h>
#include <stdlib.h>
// Fault injection only substitutes the fixture library; production encoder code is untouched.
static id<MTLLibrary> fixture_host_lib(id<MTLDevice> dev,id<MTL4Compiler> comp,const char *name,NSError **e) {
 const char *fault=getenv("NFS_SSAA_TEST_FAULT");
 if (!fault || strcmp(name,"present")) return host_msl_lib(dev,comp,name,e);
 static id<MTLLibrary> lib;
 if (!lib) {
  NSString *s=@"#include <metal_stdlib>\nusing namespace metal;\nstruct V {float4 p [[position]];float2 uv;};\nvertex V vs(uint id [[vertex_id]]) {float2 uv=float2((id<<1)&2,id&2); V o;o.p=float4(uv*float2(2,-2)+float2(-1,1),0,1);o.uv=uv;return o;}\nstruct Crop {float4 rect;float4 edge;};\nfragment float4 fs(V in [[stage_in]],texture2d<float> t [[texture(0)]],sampler s [[sampler(0)]],constant Crop& c [[buffer(0)]]){return t.sample(s,clamp(in.uv*c.rect.zw+c.rect.xy,c.edge.xy,c.edge.zw));}\n";
  if (fault && !strcmp(fault,"pipeline")) s=[s stringByAppendingString:@"fragment uint4 fsaa(){return uint4(1);}\n"];
  lib=[dev newLibraryWithSource:s options:nil error:e];
 }
 return lib;
}
#define host_msl_lib fixture_host_lib
// Real present reduction, without game data. A one-texel impulse per n*n source block
// must contribute 255/(n*n), including impulses a centre-only bilinear sample misses.
// Reuse the established host stubs; its existing crop test is not run by this entry point.
#define main present_crop_unused_main
#include "t_present_crop.m"
#undef host_msl_lib
#undef main

static id<MTLTexture> down_source(const uint8_t *rgba, int w, int h, MTLPixelFormat format) {
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:w height:h mipmapped:NO];
    d.storageMode = MTLStorageModeShared; d.usage = MTLTextureUsageShaderRead | MTLTextureUsagePixelFormatView;
    id<MTLTexture> t = [g_dev newTextureWithDescriptor:d];
    if (t) { [t replaceRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:0 withBytes:rgba bytesPerRow:w*4]; res_add(t); res_commit(); }
    return t;
}

// Both paths draw through the production encoder. The M4 variant also exercises the
// offscreen capture's own argument buffer, completion and residency lifetime.
static uint8_t *down_render(id<MTLTexture> src, const int crop[4], int w, int h, int metal4) {
    MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:w height:h mipmapped:NO];
    d.storageMode = MTLStorageModePrivate; d.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    id<MTLTexture> dst = [g_dev newTextureWithDescriptor:d];
    if (!src || !dst) { EXPECT("source and output textures allocated",1,0); return NULL; }
    if (metal4) {
        int kind = present_offscreen_wait(src,crop,dst);
        EXPECT("M4 reduction uses the standard present with MetalFX off",PRESENT_STANDARD,kind);
        if (kind != PRESENT_STANDARD) return NULL;
    } else {
        id<MTLCommandBuffer> cb = [g_q commandBuffer];
        int ok = present_encode(cb,src,dst,crop); EXPECT("legacy reduction encoded",1,ok);
        if (!ok) return NULL;
        [cb commit]; [cb waitUntilCompleted];
        EXPECT("legacy reduction completed",MTLCommandBufferStatusCompleted,cb.status);
        if (cb.status != MTLCommandBufferStatusCompleted) return NULL;
    }
    id<MTLBuffer> rb = [g_dev newBufferWithLength:(NSUInteger)w*h*4 options:MTLResourceStorageModeShared];
    id<MTLCommandBuffer> cb = [g_q commandBuffer]; id<MTLBlitCommandEncoder> bl = [cb blitCommandEncoder];
    [bl copyFromTexture:dst sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(w,h,1)
              toBuffer:rb destinationOffset:0 destinationBytesPerRow:w*4 destinationBytesPerImage:(NSUInteger)w*h*4];
    [bl endEncoding]; [cb commit]; [cb waitUntilCompleted];
    EXPECT("present readback completed",MTLCommandBufferStatusCompleted,cb.status);
    if (!rb || cb.status != MTLCommandBufferStatusCompleted) return NULL;
    uint8_t *out = malloc((size_t)w*h*4); if (out) memcpy(out,rb.contents,(size_t)w*h*4);
    return out;
}

static void down_impulse(int n, int metal4, int inset, MTLPixelFormat format) {
    const int W=8,H=6,cw=W*n,ch=H*n,sw=cw+2*inset,sh=ch+2*inset;
    uint8_t *px=malloc((size_t)sw*sh*4);
    // Magenta outside the crop catches sampling across valid-content boundaries.
    for (int y=0;y<sh;y++) for (int x=0;x<sw;x++) {
        uint8_t *p=px+4*(y*sw+x); p[0]=255;p[1]=0;p[2]=255;p[3]=255;
        if (x>=inset && x<inset+cw && y>=inset && y<inset+ch) {
            int white=(x-inset)%n==0 && (y-inset)%n==0;
            p[0]=p[1]=p[2]=white?255:0;
        }
    }
    int crop[4]={inset,inset,cw,ch};
    id<MTLTexture> src=down_source(px,sw,sh,format); free(px);
    uint8_t *out=down_render(src,crop,W,H,metal4);
    // Hand-derived block means: one white texel among 1, 4, 9 or 16 opaque texels.
    const int area_means[5]={0,255,64,28,16}; const int linear_means[5]={0,255,64,0,0};
    int active=g_ssaa_pso!=nil; const int *means=active?area_means:linear_means; int bad=0;
    if (out) for (int i=0;i<W*H;i++) bad+=abs(out[4*i]-means[n])>1 || abs(out[4*i+1]-means[n])>1 || abs(out[4*i+2]-means[n])>1 || out[4*i+3]!=255;
    else bad=W*H;
    char name[200]; snprintf(name,sizeof name,"%s %d:1 impulse mean %d, crop inset %d, %s (%d pixels)",metal4?"M4":"legacy",n,means[n],inset,format==MTLPixelFormatRGBA8Unorm_sRGB?"raw sRGB":"RGBA",W*H);
    if (bad && out) printf("  first pixel RGBA %u,%u,%u,%u\n",out[0],out[1],out[2],out[3]);
    EXPECT(name,0,bad); free(out); res_remove(src);
}

// Frozen pre-change present shader: an independent negative control used only by
// --reference-linear. The real encoder, sampler, crop and viewport stay identical.
static int down_reference_pipeline(void) {
    static const char source[] =
        "#include <metal_stdlib>\n"
        "using namespace metal;\n"
        "struct V { float4 p [[position]]; float2 uv; };\n"
        "vertex V vs(uint id [[vertex_id]]) { float2 uv=float2((id<<1)&2,id&2); V o; o.p=float4(uv*float2(2,-2)+float2(-1,1),0,1); o.uv=uv; return o; }\n"
        "struct Crop { float4 rect; float4 edge; };\n"
        "fragment float4 fs(V in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]], constant Crop& c [[buffer(0)]]) { return t.sample(s,clamp(in.uv*c.rect.zw+c.rect.xy,c.edge.xy,c.edge.zw)); }\n";
    NSError *e=nil; id<MTLLibrary> lib=[g_dev newLibraryWithSource:@(source) options:nil error:&e];
    MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];
    pd.vertexFunction=[lib newFunctionWithName:@"vs"];pd.fragmentFunction=[lib newFunctionWithName:@"fs"];
    pd.colorAttachments[0].pixelFormat=MTLPixelFormatRGBA8Unorm;
    id<MTLRenderPipelineState> pso=lib?[g_dev newRenderPipelineStateWithDescriptor:pd error:&e]:nil;
    if (!pso) { fprintf(stderr,"reference shader failed: %s\n",e.localizedDescription.UTF8String);return 0; }
    present_pipeline(MTLPixelFormatRGBA8Unorm); g_blit_pso=pso; g_ssaa_pso=nil;
    return 1;
}

static uint8_t *down_read_png(const char *path, int *w, int *h) {
    NSURL *url=[NSURL fileURLWithPath:@(path)];
    CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)url,NULL);
    CGImageRef image=source?CGImageSourceCreateImageAtIndex(source,0,NULL):NULL;
    if (!image) { if (source) CFRelease(source);fprintf(stderr,"cannot read PNG: %s\n",path);return NULL; }
    size_t iw=CGImageGetWidth(image),ih=CGImageGetHeight(image);
    if (!iw || !ih || iw>16384 || ih>16384) { CGImageRelease(image);CFRelease(source);return NULL; }
    uint8_t *rgba=calloc(iw*ih,4);CGColorSpaceRef cs=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx=rgba?CGBitmapContextCreate(rgba,iw,ih,8,iw*4,cs,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big):NULL;
    if (ctx) {
        CGContextSetBlendMode(ctx,kCGBlendModeCopy);CGContextDrawImage(ctx,CGRectMake(0,0,iw,ih),image);
        // A PNG stores straight RGBA; the bitmap decoder supplies premultiplied RGBA.
        for (size_t i=0;i<iw*ih;i++) if (rgba[4*i+3] && rgba[4*i+3]<255)
            for (int c=0;c<3;c++) rgba[4*i+c]=(uint8_t)MIN(255,(rgba[4*i+c]*255+rgba[4*i+3]/2)/rgba[4*i+3]);
        *w=(int)iw;*h=(int)ih;
    } else { free(rgba);rgba=NULL; }
    if (ctx) CGContextRelease(ctx);CGColorSpaceRelease(cs);CGImageRelease(image);CFRelease(source);
    return rgba;
}

static int down_write_png(const char *path, const uint8_t *rgba, int w, int h) {
    CGColorSpaceRef cs=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGDataProviderRef data=CGDataProviderCreateWithData(NULL,rgba,(size_t)w*h*4,NULL);
    CGImageRef image=CGImageCreate(w,h,8,32,w*4,cs,kCGImageAlphaLast|kCGBitmapByteOrder32Big,data,NULL,false,kCGRenderingIntentDefault);
    NSURL *url=[NSURL fileURLWithPath:@(path)];
    CGImageDestinationRef dest=image?CGImageDestinationCreateWithURL((__bridge CFURLRef)url,(__bridge CFStringRef)UTTypePNG.identifier,1,NULL):NULL;
    int ok=0;if (dest) { CGImageDestinationAddImage(dest,image,NULL);ok=CGImageDestinationFinalize(dest);CFRelease(dest); }
    if (image) CGImageRelease(image);CGDataProviderRelease(data);CGColorSpaceRelease(cs);
    if (!ok) fprintf(stderr,"cannot write PNG: %s\n",path);
    return ok;
}

static void down_png_roundtrip(void) {
    // Unequal top/bottom colours catch a decoder, GPU or PNG writer flipping rows;
    // the midtone also catches an unwanted sRGB decode/encode during the present.
    static const uint8_t pixels[24]={255,0,0,255, 0,255,0,255, 128,64,200,255, 11,37,91,255, 0,0,255,255, 255,255,0,255};
    char path[1024];snprintf(path,sizeof path,"%snfs-present-rgba-%d.png",NSTemporaryDirectory().UTF8String,getpid());
    EXPECT("synthetic PNG written",1,down_write_png(path,pixels,2,3));
    int w=0,h=0;uint8_t *decoded=down_read_png(path,&w,&h);unlink(path);
    EXPECT("PNG keeps width",2,w);EXPECT("PNG keeps height",3,h);
    EXPECT("PNG decode keeps top-to-bottom RGBA and midtones",1,decoded && !memcmp(decoded,pixels,sizeof pixels));
    if (!decoded) return;
    id<MTLTexture> src=down_source(decoded,w,h,MTLPixelFormatRGBA8Unorm_sRGB);free(decoded);
    for (int metal4=0;metal4<2;metal4++) {
        uint8_t *out=down_render(src,NULL,2,3,metal4);
        EXPECT(metal4?"M4 PNG pixels stay upright with raw sRGB bytes":"legacy PNG pixels stay upright with raw sRGB bytes",1,out && !memcmp(out,pixels,sizeof pixels));
        if (out) {
            EXPECT("present PNG written",1,down_write_png(path,out,2,3));
            decoded=down_read_png(path,&w,&h);unlink(path);
            EXPECT("present PNG export keeps row order and RGBA",1,decoded && w==2 && h==3 && !memcmp(decoded,pixels,sizeof pixels));
            free(decoded);free(out);
        }
    }
    res_remove(src);
}

static void resolve_parameters(void) {
    float p[4];
    present_resolve(p,8193,4096,(MTLViewport){0,0,4096,2048,0,1});
    EXPECT("true ratio just above 2 keeps three horizontal taps",3,(int)p[2]);
    EXPECT("integer vertical ratio keeps two taps",2,(int)p[3]);
    present_resolve(p,12,20,(MTLViewport){0,0,10,10,0,1});
    EXPECT("asymmetric 1.2x2 activates horizontal two taps",2,(int)p[2]);
    present_resolve(p,10,10,(MTLViewport){0,0,8,8,0,1});
    EXPECT("1.25 threshold remains single sample",1,(int)p[2]);
}
static void down_flip_alpha(int n,int metal4,int flip) {
    const int W=8,H=4,b=3,sw=W*n+2*b,sh=H*n+2*b;
    uint8_t *px=malloc((size_t)sw*sh*4);
    for(int y=0;y<sh;y++)for(int x=0;x<sw;x++) {
        uint8_t *q=px+4*(y*sw+x);q[0]=255;q[1]=0;q[2]=255;q[3]=255;
        if(x>=b&&x<sw-b&&y>=b&&y<sh-b) {
            int xx=(x-b)/n,yy=(y-b)/n;
            q[0]=20+24*xx;q[1]=30+40*yy;q[2]=170-10*xx;q[3]=50+45*yy;
        }
    }
    int crop[4]={b,b,W*n,H*n};id<MTLTexture> src=down_source(px,sw,sh,MTLPixelFormatRGBA8Unorm_sRGB);free(px);
    atomic_store(&g_origin_ll,flip);uint8_t *out=down_render(src,crop,W,H,metal4);atomic_store(&g_origin_ll,0);
    int bad=0;
    if(out)for(int y=0;y<H;y++)for(int x=0;x<W;x++) {
        int yy=flip?H-1-y:y;int want[4]={20+24*x,30+40*yy,170-10*x,50+45*yy};
        for(int c=0;c<4;c++)bad+=abs((int)out[4*(y*W+x)+c]-want[c])>1;
    } else bad=W*H*4;
    char label[128];snprintf(label,sizeof label,"%s %d:1 inset crop raw sRGB alpha flip=%d",metal4?"M4":"legacy",n,flip);
    EXPECT(label,0,bad);free(out);res_remove(src);
}
static void down_fractional(int sw,int sh,int metal4) {
    const int W=8,H=4;uint8_t *px=malloc((size_t)sw*sh*4);
    for(int y=0;y<sh;y++)for(int x=0;x<sw;x++){uint8_t *q=px+4*(y*sw+x);q[0]=q[1]=q[2]=((x+2*y)%3==0)?255:0;q[3]=255;}
    id<MTLTexture> src=down_source(px,sw,sh,MTLPixelFormatRGBA8Unorm);
    uint8_t *out=down_render(src,NULL,W,H,metal4);double mae=0,max_error=0;
    if(out)for(int y=0;y<H;y++)for(int x=0;x<W;x++){
        double x0=(double)x*sw/W,x1=(double)(x+1)*sw/W,y0=(double)y*sh/H,y1=(double)(y+1)*sh/H,mean=0;
        for(int sy=(int)floor(y0);sy<(int)ceil(y1);sy++)for(int sx=(int)floor(x0);sx<(int)ceil(x1);sx++){
            double area=fmax(0,fmin(x1,sx+1)-fmax(x0,sx))*fmax(0,fmin(y1,sy+1)-fmax(y0,sy));mean+=area*px[4*(sy*sw+sx)];
        }
        mean/=(x1-x0)*(y1-y0);double error=fabs(out[4*(y*W+x)]-mean);mae+=error;max_error=fmax(max_error,error);
    }
    printf("AREA_ORACLE %s %dx%d->%dx%d effective=%s mae=%.6f max=%.6f (encoded byte units; fractional box is approximate)\n",metal4?"M4":"legacy",sw,sh,W,H,g_ssaa_pso?"fsaa":"fs",mae/(W*H),max_error);
    EXPECT("fractional output exists",1,out!=NULL);free(px);free(out);res_remove(src);
}

static int down_cli(int argc, const char **argv) {
    const char *input=NULL,*output=NULL;int w=0,h=0,reference=0;
    for (int i=1;i<argc;i++) {
        if (!strcmp(argv[i],"--input") && i+1<argc) input=argv[++i];
        else if (!strcmp(argv[i],"--output") && i+1<argc) output=argv[++i];
        else if ((!strcmp(argv[i],"--width") || !strcmp(argv[i],"--height")) && i+1<argc) {
            int is_width=!strcmp(argv[i],"--width");char *end=NULL;long value=strtol(argv[++i],&end,10);
            if (!end || *end || value<1 || value>16384) return 2;
            if (is_width) w=(int)value;else h=(int)value;
        } else if (!strcmp(argv[i],"--reference-linear")) reference=1;
        else return 2;
    }
    if (!input || !output || !w || !h) return 2;
    int iw=0,ih=0;uint8_t *rgba=down_read_png(input,&iw,&ih);if (!rgba) return 1;
    id<MTLTexture> src=down_source(rgba,iw,ih,MTLPixelFormatRGBA8Unorm_sRGB);free(rgba);
    if (reference && !down_reference_pipeline()) { res_remove(src);return 1; }
    uint8_t *out=down_render(src,NULL,w,h,1);res_remove(src);
    int ok=out && down_write_png(output,out,w,h);free(out);
    if (ok) printf("%s present: %dx%d -> %dx%d: %s\n",reference?"reference bilinear":"production",iw,ih,w,h,output);
    return ok?0:1;
}

int main(int argc, const char **argv) { @autoreleasepool {
    if (argc==2 && !strcmp(argv[1],"--crop-only")) return present_crop_unused_main();
    mtl_init();g_fx_mode=0;atomic_store(&g_origin_ll,0);
    present_pipeline(MTLPixelFormatRGBA8Unorm);
    int wanted=getenv("DM_PRESENT_SSAA") && !strcmp(getenv("DM_PRESENT_SSAA"),"1");
    int fault=getenv("NFS_SSAA_TEST_FAULT")!=NULL;
    EXPECT("runtime selector matches effective production PSO",wanted && !fault,g_ssaa_pso!=nil);
    printf("SELECTOR requested=%d fault=%s effective=%s\n",wanted,getenv("NFS_SSAA_TEST_FAULT")?:"none",g_ssaa_pso?"fsaa":"fs");
    if (argc>1) {
        int result=down_cli(argc,argv);
        if (result==2) fprintf(stderr,"usage: %s --input image.png --output image.png --width pixels --height pixels [--reference-linear]\n",argv[0]);
        return result ? result : failed != 0;
    }
    for (int m4=0;m4<2;m4++) {
        for (int n=1;n<=4;n++) down_impulse(n,m4,0,MTLPixelFormatRGBA8Unorm);
        down_impulse(4,m4,3,MTLPixelFormatRGBA8Unorm);
        down_impulse(3,m4,2,MTLPixelFormatRGBA8Unorm_sRGB);
    }
    down_png_roundtrip();
    resolve_parameters();
    for(int m=0;m<2;m++){ for(int n=1;n<=4;n++)for(int flip=0;flip<2;flip++)down_flip_alpha(n,m,flip); down_fractional(12,6,m);down_fractional(18,9,m); }
    EXPECT("MetalFX off creates no spatial compiler",1,g_fx_comp==nil);
    printf("t_present_ssaa_toggle: %d checks, %d failed\n",cases,failed);
    return failed!=0;
} }
