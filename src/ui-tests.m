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
@interface HoverClient : NSObject
@property unsigned char limit;
@property NSUInteger reads;
@property NSUInteger writes;
@property NSError *failure;
@end
@implementation HoverClient
- (unsigned char)getMCLLimitWithError:(NSError **)error {
    self.reads++;if(error)*error=self.failure;return self.limit;
}
- (BOOL)setMCLLimit:(unsigned char)value error:(NSError **)error {
    (void)value;(void)error;self.writes++;assert(!"Hover must never write a battery setting");return NO;
}
@end

static void WaitForHintDelay(void) {
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.6]];
}
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
    HoverClient *client=[HoverClient new];client.limit=85;app.client=client;
    [app showHint:nil];assert(app.hintPanel==nil && client.reads==0);
    [app mouseEntered:nil];[app mouseExited:nil];WaitForHintDelay();
    assert(!app.hovering && app.hintPanel==nil && client.reads==0);
    NSPanel *reused=nil;
    for(NSNumber *limit in @[@80,@85,@90,@95,@100]) {
        client.limit=limit.unsignedCharValue;
        [app mouseEntered:nil];WaitForHintDelay();
        assert(app.hintPanel.visible && app.hintPanel.ignoresMouseEvents);
        assert([app.hintPanel.contentView isKindOfClass:NSGlassEffectView.class]);
        NSGlassEffectView *glass=(id)app.hintPanel.contentView;
        assert(glass.style==NSGlassEffectViewStyleRegular && glass.cornerRadius==12 && glass.contentView==app.hintView);
        assert(([app.hintView.lines[1]isEqualToString:[NSString stringWithFormat:@"Charge limit: %@%%",limit]]));
        if(reused)assert(reused==app.hintPanel);reused=app.hintPanel;
        NSUInteger reads=client.reads;[app showHint:nil];assert(client.reads==reads);
        [app mouseExited:nil];assert(!app.hintPanel.visible);
    }
    client.failure=[NSError errorWithDomain:@"Hover test" code:1 userInfo:nil];
    [app mouseEntered:nil];WaitForHintDelay();
    assert([app.hintView.lines[1]isEqualToString:@"Charge limit: Unavailable"]);
    [app hideHint];assert(!app.hintPanel.visible);
    [app mouseEntered:nil];[app hideHint];WaitForHintDelay();assert(!app.hintPanel.visible);
    assert(client.reads==6 && client.writes==0);
    HintView *hint=[[HintView alloc]initWithFrame:NSMakeRect(0,0,220,82)];
    hint.lines=@[@"ChargeCap",@"Charge limit: 85%",@"Click to adjust the charge limit"];
    hint.wantsLayer=YES;[hint updateLayer];
    assert([[hint accessibilityValue]isEqualToString:@"ChargeCap\nCharge limit: 85%\nClick to adjust the charge limit"]);
    surface=(__bridge IOSurfaceRef)hint.rasterSurface;
    assert(surface && IOSurfaceLock(surface,kIOSurfaceLockReadOnly,NULL)==kIOReturnSuccess);
    assert(((uint8_t *)IOSurfaceGetBaseAddress(surface))[3]==0);
    IOSurfaceUnlock(surface,kIOSurfaceLockReadOnly,NULL);
    [app releaseIdleSurfaces];
    assert(!app.panel && !app.view && !app.hintPanel && !app.hintView && !app.client);
    [app makePanel];[app.view updateLayer];
    assert(app.view.rasterSurface!=nil); // Reopening after cleanup must render again.
    puts("PASS: slider interaction/accessibility, glass pixels, delayed hover states/cancellation without writes, and idle cleanup/recreation.");
    return 0;
} }
