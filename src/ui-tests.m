#define main ProductMain
#import "main.m"
#undef main
#include <assert.h>

@interface SliderTarget : NSObject
@property NSInteger count;
- (void)changed:(id)sender;
@end
@implementation SliderTarget
- (void)changed:(id)sender { (void)sender;self.count++; }
@end
int main(void) { @autoreleasepool {
    [NSApplication.sharedApplication setActivationPolicy:NSApplicationActivationPolicyAccessory];
    StepSlider *slider=[[StepSlider alloc]initWithFrame:NSMakeRect(0,0,236,34)];
    slider.enabled=YES;SliderTarget *target=[SliderTarget new];slider.target=target;slider.action=@selector(changed:);
    for(int i=0;i<5;i++) {
        [slider selectPoint:NSMakePoint(12+212*i/4.,20)];
        assert(slider.limit==80+i*5);
    }
    for(int x=-100;x<400;x++) { [slider selectPoint:NSMakePoint(x,20)];assert(ValidLimit(slider.limit)); }
    assert(target.count==0); // Drag previews must not write battery settings.
    [slider setAccessibilityValue:@90];assert(slider.limit==90 && target.count==1);
    [slider setAccessibilityValue:@91];assert(slider.limit==90 && target.count==1);
    assert([slider accessibilityPerformIncrement] && slider.limit==95);
    assert([slider accessibilityPerformDecrement] && slider.limit==90);
    [slider setAccessibilityValue:@100];assert(![slider accessibilityPerformIncrement]);
    [slider setAccessibilityValue:@80];assert(![slider accessibilityPerformDecrement]);
    slider.enabled=NO;NSInteger count=target.count;
    [slider setAccessibilityValue:@100];assert(slider.limit==80 && target.count==count);
    assert(![slider accessibilityPerformIncrement]);
    ChargeApp *app=[ChargeApp new];[app makePanel];[app.view updateLayer];
    IOSurfaceRef surface=(__bridge IOSurfaceRef)app.view.rasterSurface;
    assert(surface && IOSurfaceGetPixelFormat(surface)==0x42475241);
    assert(IOSurfaceLock(surface,kIOSurfaceLockReadOnly,NULL)==kIOReturnSuccess);
    uint8_t *pixels=IOSurfaceGetBaseAddress(surface);
    size_t width=IOSurfaceGetWidth(surface),height=IOSurfaceGetHeight(surface),stride=IOSurfaceGetBytesPerRow(surface);
    assert(pixels[3]==0); // Rounded corners must remain transparent.
    uint8_t alpha=pixels[(height/2)*stride+(width/2)*4+3];
    if(!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency)assert(alpha>150 && alpha<200);
    else assert(alpha==255);
    IOSurfaceUnlock(surface,kIOSurfaceLockReadOnly,NULL);
    [app.view.slider updateLayer];
    surface=(__bridge IOSurfaceRef)app.view.slider.rasterSurface;
    assert(surface && IOSurfaceLock(surface,kIOSurfaceLockReadOnly,NULL)==kIOReturnSuccess);
    CGFloat scale=app.view.slider.window.backingScaleFactor?:2;
    size_t x=(size_t)(64*scale),y=(size_t)(20*scale);
    pixels=IOSurfaceGetBaseAddress(surface);stride=IOSurfaceGetBytesPerRow(surface);
    assert(pixels[y*stride+x*4+3]>240 && pixels[y*stride+x*4+2]>230);
    IOSurfaceUnlock(surface,kIOSurfaceLockReadOnly,NULL);
    puts("PASS: five slider stops, clamping, drag preview isolation, accessibility actions, disabled-state guards, and glass/slider surface pixels.");
    return 0;
} }
