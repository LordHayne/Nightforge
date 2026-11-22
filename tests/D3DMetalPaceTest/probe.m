// A program like a Wine process on D3DMetal: loads an image named like D3DMetal.framework (argv[1], "-" for none),
// presents through a command buffer and sets its layer's display sync off, and says what Metal was asked:
// "redirected <n> sync <0|1>" – n presents that went to presentDrawable:afterMinimumDuration:. With
// NIGHTFORGE_TEST_REENTER set, that one hands on to presentDrawable: itself, as a later Metal might: the library has
// to take Metal's own then, not loop.
#import <Metal/Metal.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int redirected = 0;
static int reenter = 0;
static void (*originalAfter)(id, SEL, id, CFTimeInterval);

static void countedAfter(id self, SEL _cmd, id drawable, CFTimeInterval duration) {
    if (duration > 0.016 && duration < 0.017) redirected++;  // 1/60
    if (reenter) {
        ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(presentDrawable:), drawable);
        return;
    }
    originalAfter(self, _cmd, drawable, duration);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        Method after = class_getInstanceMethod(objc_getClass("_MTLCommandBuffer"), @selector(presentDrawable:afterMinimumDuration:));
        if (!after) { printf("no-class\n"); return 0; }
        originalAfter = (void *)method_setImplementation(after, (IMP)countedAfter);
        reenter = getenv("NIGHTFORGE_TEST_REENTER") != NULL;
        if (argc > 1 && strcmp(argv[1], "-") != 0 && !dlopen(argv[1], RTLD_NOW)) { printf("dlopen failed\n"); return 2; }
        usleep(500000);  // the library takes hold after dyld is done
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        id<MTLCommandQueue> queue = [device newCommandQueue];
        CAMetalLayer *layer = [CAMetalLayer layer];
        layer.device = device;
        layer.drawableSize = CGSizeMake(64, 64);
        layer.displaySyncEnabled = NO;
        for (int i = 0; i < 3; i++) {
            id<CAMetalDrawable> drawable = [layer nextDrawable];
            id<MTLCommandBuffer> buffer = [queue commandBuffer];
            MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
            pass.colorAttachments[0].texture = drawable.texture;
            pass.colorAttachments[0].loadAction = MTLLoadActionClear;
            [[buffer renderCommandEncoderWithDescriptor:pass] endEncoding];
            [buffer presentDrawable:drawable];
            [buffer commit];
            [buffer waitUntilCompleted];
        }
        printf("redirected %d sync %d\n", redirected, layer.displaySyncEnabled ? 1 : 0);
    }
    return 0;
}
