#import <AppKit/AppKit.h>
#import <mach/mach.h>
#import <QuartzCore/QuartzCore.h>
#import <IOSurface/IOSurface.h>
#include <sys/file.h>
#include <fcntl.h>
#include <errno.h>
#import "charge.h"

// WindowServer's native backdrop blur avoids creating a separate local effect renderer.
// This private per-window API is also used by native terminal/windowing implementations.
static int32_t LastBlurError;
static BOOL ApplyBackdrop(NSWindow *window) {
    static int32_t (*connection)(void);
    static int32_t (*blur)(int32_t,uint32_t,uint32_t);
    static BOOL loaded;
    if(!loaded) {
        loaded=YES;
        void *library=dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_LAZY|RTLD_LOCAL);
        if(library){connection=dlsym(library,"SLSMainConnectionID");blur=dlsym(library,"SLSSetWindowBackgroundBlurRadius");}
    }
    if(!connection||!blur)return NO;
    uint32_t radius=NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency?0:36;
    LastBlurError=blur(connection(),(uint32_t)window.windowNumber,radius);return LastBlurError==0;
}

static NSColor *Green(void) { return [NSColor colorWithSRGBRed:0.10 green:0.65 blue:0.43 alpha:1]; }
static NSColor *Muted(NSView *view) {
    BOOL dark=[[view.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]]isEqual:NSAppearanceNameDarkAqua];
    return [NSColor colorWithWhite:dark?.94:.08 alpha:.72];
}
static void Round(NSRect r, CGFloat radius, NSColor *color) { [color setFill]; [[NSBezierPath bezierPathWithRoundedRect:r xRadius:radius yRadius:radius] fill]; }
static void Text(NSString *s, NSPoint point, CGFloat size, NSFontWeight weight, NSColor *color) {
    @autoreleasepool { [s drawAtPoint:point withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:size weight:weight], NSForegroundColorAttributeName:color}]; }
}
static void Battery(NSRect r, CGFloat fill, NSColor *color) {
    [color set]; NSBezierPath *p=[NSBezierPath bezierPathWithRoundedRect:r xRadius:2.2 yRadius:2.2];p.lineWidth=1.35;[p stroke];
    Round(NSMakeRect(NSMaxX(r)+1.4,NSMidY(r)-1.8,1.5,3.6),.7,color);
    Round(NSMakeRect(r.origin.x+2.5,r.origin.y+2.5,(r.size.width-5)*fill,r.size.height-5),.7,color);
    p=[NSBezierPath bezierPath];p.lineWidth=1.1;
    CGFloat x=NSMaxX(r)-3.3;[p moveToPoint:NSMakePoint(x,NSMinY(r)-1.5)];[p lineToPoint:NSMakePoint(x,NSMaxY(r)+1.5)];[p stroke];
}
static NSImage *StatusIcon(void) {
    NSImage *image=[[NSImage alloc]initWithSize:NSMakeSize(22,18)];
    [image lockFocus];Battery(NSMakeRect(1.5,4,16,10),.73,NSColor.blackColor);[image unlockFocus];image.template=YES;return image;
}
static double KernelPeak;
static double Footprint(void) {
    task_vm_info_data_t t={0};mach_msg_type_number_t c=TASK_VM_INFO_COUNT;
    if(task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&t,&c)!=KERN_SUCCESS||c<TASK_VM_INFO_REV3_COUNT){KernelPeak=INFINITY;return INFINITY;}
    if(c>=TASK_VM_INFO_REV3_COUNT && t.ledger_phys_footprint_peak>0)KernelPeak=t.ledger_phys_footprint_peak/1000000.0;
    return t.phys_footprint/1000000.0;
}

@interface ChargePanel : NSPanel
@end
@implementation ChargePanel
- (BOOL)canBecomeKeyWindow { return YES; }

@end

static void PaintSurface(NSView *view,id __strong *storage) {
    // ponytail: one shared surface per control; add buffering if tearing is observed.
    // This avoids vector-renderer caches and repeated bitmap copies.
    @autoreleasepool {
        CGFloat scale=view.window.backingScaleFactor?:2;
        size_t width=MAX(1,(size_t)ceil(view.bounds.size.width*scale));
        size_t height=MAX(1,(size_t)ceil(view.bounds.size.height*scale));
        IOSurfaceRef surface=(__bridge IOSurfaceRef)(*storage);
        if(!surface||IOSurfaceGetWidth(surface)!=width||IOSurfaceGetHeight(surface)!=height) {
            surface=IOSurfaceCreate((__bridge CFDictionaryRef)@{
                (__bridge NSString *)kIOSurfaceWidth:@(width),(__bridge NSString *)kIOSurfaceHeight:@(height),
                (__bridge NSString *)kIOSurfaceBytesPerElement:@4,(__bridge NSString *)kIOSurfaceBytesPerRow:@(width*4),
                (__bridge NSString *)kIOSurfacePixelFormat:@(0x42475241)});
            if(!surface)return;
            *storage=CFBridgingRelease(surface);
        }
        if(IOSurfaceLock(surface,0,NULL)!=kIOReturnSuccess)return;
        CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();
        CGContextRef context=CGBitmapContextCreate(IOSurfaceGetBaseAddress(surface),width,height,8,IOSurfaceGetBytesPerRow(surface),color,kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little);
        CGColorSpaceRelease(color);
        if(context) {
            CGContextClearRect(context,CGRectMake(0,0,width,height));CGContextScaleCTM(context,scale,scale);
            [NSGraphicsContext saveGraphicsState];
            NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithCGContext:context flipped:NO];
            [view drawRect:view.bounds];[NSGraphicsContext restoreGraphicsState];CGContextRelease(context);
        }
        IOSurfaceUnlock(surface,0,NULL);
        [CATransaction begin];[CATransaction setDisableActions:YES];
        view.layer.contentsFormat=kCAContentsFormatRGBA8Uint;view.layer.contentsScale=scale;
        view.layer.contents=nil;view.layer.contents=(__bridge id)surface;
        [CATransaction commit];
    }
}

// A small native control avoids the large rendering caches of macOS's stock slider.
// The panel uses the native compositor backdrop and system accessibility settings.
@interface StepSlider : NSControl
@property (strong) id rasterSurface;
@property NSInteger limit;
@property (copy) void (^preview)(void);
- (void)selectPoint:(NSPoint)point;
@end
@implementation StepSlider
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer { PaintSurface(self,&_rasterSurface); }
- (BOOL)acceptsFirstResponder { return self.enabled; }
- (NSTextInputContext *)inputContext { return nil; }
- (NSString *)accessibilityRole { return NSAccessibilitySliderRole; }
- (NSString *)accessibilityLabel { return @"Battery charge limit"; }
- (id)accessibilityValue { return @(self.limit); }
- (NSString *)accessibilityValueDescription { return [NSString stringWithFormat:@"%ld percent",(long)self.limit]; }
- (id)accessibilityMinValue { return @80; }
- (id)accessibilityMaxValue { return @100; }
- (void)setAccessibilityValue:(id)value {
    if ([value isKindOfClass:NSNumber.class] && ValidLimit([value integerValue]) && self.enabled) {
        self.limit=[value integerValue];[self sendAction:self.action to:self.target];self.needsDisplay=YES;
    }
}
- (BOOL)accessibilityPerformIncrement { if(!self.enabled||self.limit>=100)return NO;[self setAccessibilityValue:@(self.limit+5)];return YES; }
- (BOOL)accessibilityPerformDecrement { if(!self.enabled||self.limit<=80)return NO;[self setAccessibilityValue:@(self.limit-5)];return YES; }
- (void)drawRect:(NSRect)dirty {
    (void)dirty;CGFloat width=self.bounds.size.width-24,x=12+width*(self.limit-80)/20.0;
    NSColor *ink=self.enabled?Green():NSColor.disabledControlTextColor;
    Round(NSMakeRect(12,17,width,6),3,[NSColor.labelColor colorWithAlphaComponent:.12]);
    if(x>12)Round(NSMakeRect(12,17,x-12,6),3,ink);
    for(int i=0;i<5;i++) { CGFloat tx=12+width*i/4.;Round(NSMakeRect(tx-.9,5,1.8,1.8),.9,i*5+80<=self.limit?ink:NSColor.tertiaryLabelColor); }
    [NSGraphicsContext saveGraphicsState];
    NSBezierPath *knob=[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x-12,9,24,22) xRadius:11 yRadius:11];
    [[NSColor colorWithWhite:.97 alpha:.98]setFill];[knob fill];
    [NSGraphicsContext restoreGraphicsState];knob.lineWidth=.7;[[NSColor.whiteColor colorWithAlphaComponent:.9]setStroke];[knob stroke];
    if(self.window.firstResponder==self && NSApp.currentEvent.type==NSEventTypeKeyDown) {
        [[NSColor keyboardFocusIndicatorColor]setStroke];NSBezierPath *focus=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(knob.bounds,-3,-3) xRadius:14 yRadius:14];focus.lineWidth=2;[focus stroke];
    }
}
- (void)selectPoint:(NSPoint)p {
    double fraction=fmin(1,fmax(0,(p.x-12)/(self.bounds.size.width-24)));
    NSInteger value=80+5*(NSInteger)llround(fraction*4);
    if(self.limit!=value) { self.limit=value;self.needsDisplay=YES;if(self.preview)self.preview(); }
}
- (void)mouseDown:(NSEvent *)event {
    if(!self.enabled)return;[self.window makeFirstResponder:self];
    [self selectPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    while(event.type!=NSEventTypeLeftMouseUp) {
        @autoreleasepool {
            [self.window displayIfNeeded];
            event=[self.window nextEventMatchingMask:NSEventMaskLeftMouseDragged|NSEventMaskLeftMouseUp];
            if(event)[self selectPoint:[self convertPoint:event.locationInWindow fromView:nil]];
        }
        if(!event)break;
    }
    [self sendAction:self.action to:self.target];
}
- (void)keyDown:(NSEvent *)event {
    if(event.keyCode==123||event.keyCode==125)[self accessibilityPerformDecrement];
    else if(event.keyCode==124||event.keyCode==126)[self accessibilityPerformIncrement];
    else [super keyDown:event];
}
@end

@interface SmallControl : NSControl
@property (strong) id rasterSurface;
@property NSString *label;
@property BOOL toggle;
@property BOOL on;
@end
@implementation SmallControl
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer { PaintSurface(self,&_rasterSurface); }
- (BOOL)acceptsFirstResponder { return self.enabled; }
- (NSTextInputContext *)inputContext { return nil; }
- (NSString *)accessibilityRole { return self.toggle?NSAccessibilityCheckBoxRole:NSAccessibilityButtonRole; }
- (NSString *)accessibilityLabel { return self.label; }
- (id)accessibilityValue { return self.toggle?@(self.on):nil; }
- (BOOL)accessibilityPerformPress { if(!self.enabled)return NO;[self sendAction:self.action to:self.target];return YES; }
- (void)mouseDown:(NSEvent *)event {
    if(!self.enabled)return;[self.window makeFirstResponder:self];
    while(event.type!=NSEventTypeLeftMouseUp) {
        event=[self.window nextEventMatchingMask:NSEventMaskLeftMouseDragged|NSEventMaskLeftMouseUp];
        if(!event)return;
    }
    if(NSPointInRect([self convertPoint:event.locationInWindow fromView:nil],self.bounds))[self accessibilityPerformPress];
}
- (void)keyDown:(NSEvent *)event { if(event.keyCode==49||event.keyCode==36)[self accessibilityPerformPress];else [super keyDown:event]; }
- (void)drawRect:(NSRect)dirty {
    (void)dirty;
    if(self.toggle) {
        Round(NSMakeRect(0,3,30,18),9,self.on?Green():[NSColor.labelColor colorWithAlphaComponent:.16]);
        Round(NSMakeRect(self.on?14:2,5,14,14),7,NSColor.whiteColor);
    } else Text(self.label,NSMakePoint(0,5),11,NSFontWeightRegular,Muted(self));
    if(self.window.firstResponder==self && NSApp.currentEvent.type==NSEventTypeKeyDown) {
        [[NSColor keyboardFocusIndicatorColor]setStroke];NSBezierPath *p=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,1) xRadius:5 yRadius:5];[p stroke];
    }
}
@end

@interface ChargeView : NSView
@property StepSlider *slider;
@property SmallControl *optimized;
@property NSString *issue;
@property (strong) id rasterSurface;
@end
@implementation ChargeView
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer { PaintSurface(self,&_rasterSurface); }

- (void)drawRect:(NSRect)dirty {
    [super drawRect:dirty];
    CGContextClearRect(NSGraphicsContext.currentContext.CGContext,NSRectToCGRect(dirty));
    NSBezierPath *surface=[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,.5,.5) xRadius:20 yRadius:20];
    BOOL dark=[[self.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]]isEqual:NSAppearanceNameDarkAqua];
    if(NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency) { [NSColor.windowBackgroundColor setFill];[surface fill]; }
    else {
        [[NSColor colorWithWhite:dark?.16:.98 alpha:dark?.69:.66]setFill];[surface fill];
    }
    surface.lineWidth=1;[[NSColor colorWithWhite:1 alpha:dark?.23:.66]setStroke];[surface stroke];
    NSColor *ink=NSColor.labelColor,*muted=Muted(self);
    Text(@"Charge Limit",NSMakePoint(18,172),13,NSFontWeightMedium,ink);
    Battery(NSMakeRect(215,174,23,13),self.slider.limit/100.,muted);
    Text(self.slider.enabled?[NSString stringWithFormat:@"%ld",(long)self.slider.limit]:@"—",NSMakePoint(17,130),30,NSFontWeightMedium,ink);
    Text(@"%",NSMakePoint(self.slider.limit==100?80:61,135),21,NSFontWeightRegular,muted);
    Text(@"Maximum battery charge",NSMakePoint(19,116),11,NSFontWeightRegular,muted);
    CGFloat width=self.slider.bounds.size.width-24;
    for(int i=0;i<5;i++) {
        NSString *label=[NSString stringWithFormat:@"%d",80+i*5];
        CGFloat w=[label sizeWithAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:11]}].width;
        CGFloat x=self.slider.frame.origin.x+12+width*i/4.-w/2.;
        Text(label,NSMakePoint(x,62),11,NSFontWeightRegular,self.slider.limit==80+i*5?ink:muted);
    }
    if(self.issue) {
        [self.issue drawInRect:NSMakeRect(18,31,224,27) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:11],NSForegroundColorAttributeName:muted}];
    } else if(!self.optimized.hidden) {
        Text(@"Optimized Battery Charging",NSMakePoint(18,40),11,NSFontWeightRegular,ink);
    } else {
        Round(NSMakeRect(19,44,5,5),2.5,Green());Text(@"Limit set in macOS",NSMakePoint(30,40),11,NSFontWeightRegular,muted);
    }
    [NSColor.separatorColor setFill];NSRectFill(NSMakeRect(15,28,226,.5));
}
- (void)cancelOperation:(id)sender { (void)sender;[NSApp.delegate performSelector:@selector(closePanel:) withObject:nil]; }
@end

@interface ChargeApp : NSObject <NSApplicationDelegate>
@property NSStatusItem *item;
@property ChargePanel *panel;
@property ChargeView *view;
@property id client;
@property id globalMonitor;
@property id localMonitor;
@property BOOL verifying;
@property BOOL profiling;
@property BOOL failed;
@property double peak;
@property NSInteger originalLimit;
@property BOOL originalOptimized;
@property BOOL originalSettingsCaptured;
@property int cycle;
@end
@implementation ChargeApp
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    (void)note;self.item=[[NSStatusBar systemStatusBar]statusItemWithLength:NSSquareStatusItemLength];
    self.item.button.image=StatusIcon();self.item.button.target=self;self.item.button.action=@selector(togglePanel:);
    self.item.button.accessibilityLabel=@"ChargeCap battery charge limit";
    self.item.autosaveName=@"ChargeCap";self.item.visible=YES;
    if(self.verifying || self.profiling) {
        [self performSelector:self.profiling?@selector(profileOpen):@selector(beginVerification) withObject:nil afterDelay:3];
    }
}
- (void)profileOpen {
    printf("Profile idle %.3f MB\n",Footprint());[self togglePanel:nil];
    printf("Window %ld initial %.3f MB\n",(long)self.panel.windowNumber,Footprint());fflush(stdout);
    if(getenv("CHARGECAP_PROFILE_KEY")){[self.panel makeKeyWindow];[self.panel makeFirstResponder:self.view.slider];}
    [self performSelector:@selector(profileReport) withObject:nil afterDelay:25];
    if(getenv("CHARGECAP_PROFILE_CYCLES"))[self performSelector:@selector(profileCycle) withObject:nil afterDelay:2];
}
- (void)profileCycle {
    [self closePanel:nil];[self togglePanel:nil];
    if(++self.cycle<5)[self performSelector:@selector(profileCycle) withObject:nil afterDelay:2];
}
- (void)profileReport { [self sample:nil];printf("Profile visible %.3f MB; peak %.3f MB\n",Footprint(),self.peak);fflush(stdout);[self finishVerification]; }
- (void)makePanel {
    self.panel=[[ChargePanel alloc]initWithContentRect:NSMakeRect(0,0,256,200) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    self.panel.colorSpace=NSColorSpace.sRGBColorSpace;self.panel.backgroundColor=NSColor.clearColor;self.panel.opaque=NO;self.panel.hasShadow=NO;self.panel.level=NSPopUpMenuWindowLevel;self.panel.hidesOnDeactivate=NO;
    self.view=[[ChargeView alloc]initWithFrame:NSMakeRect(0,0,256,200)];
    self.view.wantsLayer=YES;self.panel.contentView=self.view;
    StepSlider *slider=[[StepSlider alloc]initWithFrame:NSMakeRect(12,78,232,34)];slider.limit=85;slider.enabled=YES;slider.target=self;slider.action=@selector(changeLimit:);
    __weak ChargeApp *weakSelf=self;
    slider.preview=^{
        [weakSelf.view setNeedsDisplayInRect:NSMakeRect(16,126,200,48)];
        [weakSelf.view setNeedsDisplayInRect:NSMakeRect(12,58,232,18)];
        [weakSelf.view setNeedsDisplayInRect:NSMakeRect(213,172,30,16)];
    };self.view.slider=slider;[self.view addSubview:slider];
    SmallControl *optimized=[[SmallControl alloc]initWithFrame:NSMakeRect(208,32,32,26)];optimized.toggle=YES;optimized.enabled=YES;optimized.label=@"Optimized Battery Charging";optimized.target=self;optimized.action=@selector(changeOptimized:);self.view.optimized=optimized;[self.view addSubview:optimized];
    SmallControl *settings=[[SmallControl alloc]initWithFrame:NSMakeRect(18,2,58,25)];settings.label=@"Settings…";settings.enabled=YES;settings.target=self;settings.action=@selector(openSettings:);[self.view addSubview:settings];
    SmallControl *quit=[[SmallControl alloc]initWithFrame:NSMakeRect(211,2,32,25)];quit.label=@"Quit";quit.enabled=YES;quit.target=self;quit.action=@selector(quit:);[self.view addSubview:quit];
    slider.nextKeyView=optimized;optimized.nextKeyView=settings;settings.nextKeyView=quit;quit.nextKeyView=slider;
}
- (void)refresh {
    NSError *error=nil;if(self.profiling)printf("Before backend %.3f MB\n",Footprint());if(!self.client)self.client=ChargeClient(&error);
    if(self.profiling)printf("Client created %.3f MB\n",Footprint());
    NSInteger value=0;self.view.issue=error.localizedDescription?:ReadLimit(self.client,&value);
    self.view.slider.enabled=self.view.issue==nil;
    if(!self.view.issue)self.view.slider.limit=value;
    self.view.optimized.hidden=self.view.issue!=nil || value!=100;
    if(value==100 && !self.view.issue) {
        BOOL enabled=NO;NSString *issue=ReadOptimized(self.client,&enabled);
        self.view.optimized.enabled=!issue;self.view.optimized.on=enabled;if(issue){self.view.issue=issue;self.view.optimized.hidden=YES;}
    }
    if(self.profiling)printf("Native state read %.3f MB\n",Footprint());
    self.view.needsDisplay=YES;self.view.optimized.needsDisplay=YES;self.view.slider.needsDisplay=YES;
}
- (void)togglePanel:(id)sender {
    (void)sender;if(self.panel.visible){[self closePanel:nil];return;}
    if(!self.panel)[self makePanel];[self refresh];
    NSButton *button=self.item.button;NSRect anchor=[button.window convertRectToScreen:[button convertRect:button.bounds toView:nil]];
    NSScreen *screen=button.window.screen?:NSScreen.mainScreen;
    NSPoint pointer=NSEvent.mouseLocation;
    // Hosted status items may expose a placeholder frame before their first click.
    if(anchor.size.width<=1 || !NSIntersectsRect(anchor,screen.frame) || NSMaxY(anchor)<NSMaxY(screen.visibleFrame)) {
        for(NSScreen *candidate in NSScreen.screens)if(NSPointInRect(pointer,candidate.frame)){screen=candidate;break;}
        anchor=NSMakeRect(pointer.x-11,NSMaxY(screen.visibleFrame),22,22);
    }
    CGFloat x=fmin(fmax(NSMidX(anchor)-128,NSMinX(screen.visibleFrame)+8),NSMaxX(screen.visibleFrame)-264);
    [self.panel setFrameOrigin:NSMakePoint(x,NSMaxY(screen.visibleFrame)-206)];
    [self.panel orderFrontRegardless];
    BOOL backdrop=ApplyBackdrop(self.panel);
    if(self.profiling||self.verifying){printf("Native backdrop: %s (window %ld, error %d)\n",backdrop?"confirmed":"unavailable",(long)self.panel.windowNumber,LastBlurError);fflush(stdout);}
    if(!backdrop && self.panel.contentView==self.view) {
        NSVisualEffectView *fallback=[[NSVisualEffectView alloc]initWithFrame:self.view.bounds];
        fallback.material=NSVisualEffectMaterialPopover;fallback.blendingMode=NSVisualEffectBlendingModeBehindWindow;fallback.state=NSVisualEffectStateActive;
        self.panel.contentView=fallback;[fallback addSubview:self.view];
    }
    [button highlight:YES];
    __weak ChargeApp *weakSelf=self;
    self.globalMonitor=[NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown|NSEventMaskRightMouseDown handler:^(NSEvent *e){(void)e;[weakSelf closePanel:nil];}];
    self.localMonitor=[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown|NSEventMaskRightMouseDown|NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event){
        if(event.type==NSEventTypeKeyDown && event.keyCode==53){[weakSelf closePanel:nil];return nil;}
        if(event.type!=NSEventTypeKeyDown && event.window!=weakSelf.panel && event.window!=weakSelf.item.button.window)[weakSelf closePanel:nil];return event;
    }];
}
- (void)closePanel:(id)sender {
    (void)sender;[self.panel orderOut:nil];[self.item.button highlight:NO];
    if(self.globalMonitor){[NSEvent removeMonitor:self.globalMonitor];self.globalMonitor=nil;}
    if(self.localMonitor){[NSEvent removeMonitor:self.localMonitor];self.localMonitor=nil;}
}
- (void)changeLimit:(StepSlider *)slider {
    NSString *issue=WriteLimit(self.client,slider.limit);[self refresh];if(issue){self.view.issue=issue;self.view.needsDisplay=YES;}
}
- (void)changeOptimized:(id)sender {
    (void)sender;NSInteger current=0;
    if(ReadLimit(self.client,&current)||current!=100){[self refresh];return;}
    NSString *issue=WriteOptimized(self.client,!self.view.optimized.on);[self refresh];if(issue){self.view.issue=issue;self.view.needsDisplay=YES;}
}
- (void)openSettings:(id)sender { (void)sender;[self closePanel:nil];[[NSWorkspace sharedWorkspace]openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.Battery-Settings.extension"]]; }
- (void)quit:(id)sender { (void)sender;[self closePanel:nil];[NSApp terminate:nil]; }
- (void)sample:(id)sender {
    (void)sender;double current=Footprint(),value=fmax(current,KernelPeak);
    if(self.verifying && self.peak<10.13 && value>=10.13)fprintf(stderr,"Budget crossing: step=%d visible=%d current=%.3f MB kernel peak=%.3f MB\n",self.cycle,self.panel.visible,current,KernelPeak);
    if(value>self.peak)self.peak=value;
}
- (void)beginVerification {
    printf("Idle: %.3f MB\n",Footprint());fflush(stdout);[self togglePanel:nil];
    NSString *issue=ReadLimit(self.client,&_originalLimit);if(!issue)issue=ReadOptimized(self.client,&_originalOptimized);
    if(issue){fprintf(stderr,"Verification unavailable: %s\n",issue.UTF8String);self.failed=YES;[self finishVerification];return;}
    self.originalSettingsCaptured=YES;
    printf("Original: %ld%%; optimized=%s; panel=%s; window=%ld\n",(long)self.originalLimit,self.originalOptimized?"on":"off",NSStringFromRect(self.panel.frame).UTF8String,(long)self.panel.windowNumber);fflush(stdout);
    [self.panel makeKeyWindow];[self.panel makeFirstResponder:self.view.slider];
    NSInteger next=self.originalLimit==100?95:self.originalLimit+5;
    [self.view.slider setAccessibilityValue:@(next)];
    if(self.view.issue||self.view.slider.limit!=next)self.failed=YES;
    [self.view.slider setAccessibilityValue:@(self.originalLimit)];
    if(self.view.issue||self.view.slider.limit!=self.originalLimit)self.failed=YES;
    NSEvent *right=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:self.panel.windowNumber context:nil characters:@"\uf703" charactersIgnoringModifiers:@"\uf703" isARepeat:NO keyCode:124];
    [self.panel sendEvent:right];
    if(self.view.slider.limit!=MIN(100,self.originalLimit+5))self.failed=YES;
    [self.view.slider setAccessibilityValue:@(self.originalLimit)];
    NSPoint end=NSMakePoint(12+(self.view.slider.bounds.size.width-24)*(self.originalLimit-80)/20.,20);
    NSPoint point=[self.view.slider convertPoint:end toView:nil];
    NSEvent *down=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:point modifierFlags:0 timestamp:0 windowNumber:self.panel.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];
    NSEvent *drag=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDragged location:point modifierFlags:0 timestamp:0 windowNumber:self.panel.windowNumber context:nil eventNumber:2 clickCount:1 pressure:1];
    NSEvent *up=[NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:point modifierFlags:0 timestamp:0 windowNumber:self.panel.windowNumber context:nil eventNumber:3 clickCount:1 pressure:0];
    [NSApp postEvent:drag atStart:NO];[NSApp postEvent:up atStart:NO];[self.view.slider mouseDown:down];
    if(self.view.issue||self.view.slider.limit!=self.originalLimit)self.failed=YES;
    puts("Checked: mouse tracking, keyboard event routing, and accessibility adjustment.");
    [self performSelector:@selector(verificationCycle) withObject:nil afterDelay:2];
}
- (void)verificationCycle {
    @autoreleasepool {
        if(self.cycle==5){[self finishVerification];return;}
        NSInteger value=80+self.cycle*5;self.view.slider.limit=value;[self changeLimit:self.view.slider];
        if(self.view.issue||self.view.slider.limit!=value||self.view.optimized.hidden!=(value!=100))self.failed=YES;
        printf("%ld%%: %s; %.3f MB\n",(long)value,self.view.issue.UTF8String?:"verified",Footprint());fflush(stdout);
        if(value==100) {
            [self.view.optimized accessibilityPerformPress];BOOL observed=self.originalOptimized;
            NSString *issue=ReadOptimized(self.client,&observed);
            if(!issue && observed==self.originalOptimized)issue=@"Optimized control did not change the setting.";
            [self.view.optimized accessibilityPerformPress];BOOL restored=!self.originalOptimized;
            NSString *restoreIssue=ReadOptimized(self.client,&restored);
            if(!restoreIssue && restored!=self.originalOptimized)restoreIssue=@"Optimized control did not restore the setting.";
            issue=issue?:restoreIssue;
            if(issue){self.failed=YES;fprintf(stderr,"Optimized toggle failed: %s\n",issue.UTF8String);}else puts("PASS: optimized control toggled and restored.");
            [self refresh];
        }
        [self closePanel:nil];self.cycle++;[self togglePanel:nil];
    }
    [self performSelector:@selector(verificationCycle) withObject:nil afterDelay:self.cycle==5?5:1];
}
- (void)finishVerification {
    if(self.originalSettingsCaptured) {
        NSString *limitIssue=WriteLimit(self.client,self.originalLimit);
        NSString *optimizedIssue=WriteOptimized(self.client,self.originalOptimized);
        NSString *issue=limitIssue?:optimizedIssue;
        if(issue){self.failed=YES;fprintf(stderr,"RESTORE FAILED: %s\n",issue.UTF8String);}else puts("PASS: original settings restored.");
    }
    [self closePanel:nil];[self sample:nil];
    printf("After use: %.3f MB; kernel peak: %.3f MB; 10.13 MB target: %s\n",Footprint(),self.peak,self.peak<10.13?"PASS":"FAIL");fflush(stdout);
    if(self.verifying && self.peak>=10.13)self.failed=YES;
    [NSApp stop:nil];
    [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0]atStart:NO];
}
@end

int main(int argc,const char **argv) {
    @autoreleasepool {
        if(argc==2 && strcmp(argv[1],"--diagnose")==0) {
            NSError *error=nil;id client=ChargeClient(&error);NSInteger limit=0;BOOL optimized=NO;
            NSString *issue=error.localizedDescription?:ReadLimit(client,&limit);if(!issue)issue=ReadOptimized(client,&optimized);
            if(issue){fprintf(stderr,"%s\n",issue.UTF8String);return 1;}
            printf("Charge limit: %ld%%; Optimized Battery Charging: %s\n",(long)limit,optimized?"on":"off");return 0;
        }
        BOOL verify=argc==2 && strcmp(argv[1],"--verify")==0;
        BOOL profile=argc==2 && strcmp(argv[1],"--profile")==0;
        if(argc!=1 && !verify && !profile){fprintf(stderr,"Usage: ChargeCap [--diagnose | --verify | --profile]\n");return 2;}
        NSString *lockPath=[NSTemporaryDirectory()stringByAppendingPathComponent:@"local.amogh.ChargeCap.lock"];
        int lock=open(lockPath.fileSystemRepresentation,O_CREAT|O_RDWR|O_CLOEXEC|O_NOFOLLOW,0600);
        if(lock<0){perror("ChargeCap lock");return 1;}
        if(flock(lock,LOCK_EX|LOCK_NB)!=0){int reason=errno;close(lock);if(reason==EWOULDBLOCK)return 0;errno=reason;perror("ChargeCap lock");return 1;}
        NSApplication *app;ChargeApp *delegate;
        @autoreleasepool { app=NSApplication.sharedApplication;[app setActivationPolicy:NSApplicationActivationPolicyAccessory];delegate=[ChargeApp new];delegate.verifying=verify;delegate.profiling=profile;app.delegate=delegate; }
        [app run];return delegate.failed?1:0;
    }
}
