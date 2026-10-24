#import <AppKit/AppKit.h>
static NSColor *RGB(unsigned value, CGFloat alpha) {
    return [NSColor colorWithSRGBRed:((value>>16)&255)/255.0 green:((value>>8)&255)/255.0 blue:(value&255)/255.0 alpha:alpha];
}
static NSBezierPath *Round(NSRect rect, CGFloat r) { return [NSBezierPath bezierPathWithRoundedRect:rect xRadius:r yRadius:r]; }
int main(int argc, const char **argv) { @autoreleasepool {
    if (argc != 2) return 2;
    NSString *folder = [NSString stringWithUTF8String:argv[1]];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSNumber *sizeValue in @[@16,@32,@64,@128,@256,@512,@1024]) {
        NSInteger size = sizeValue.integerValue;
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:size pixelsHigh:size bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];
        NSAffineTransform *scale = [NSAffineTransform transform];[scale scaleBy:size/1024.0];[scale concat];
        NSBezierPath *tile=Round(NSMakeRect(32,32,960,960),216);
        NSGradient *background=[[NSGradient alloc] initWithColors:@[RGB(0xc8e6d9,1),RGB(0xe8f6ee,1),RGB(0xfbfff9,1)]];
        [background drawInBezierPath:tile angle:62];
        [NSGraphicsContext saveGraphicsState];[tile addClip];
        NSGradient *glow=[[NSGradient alloc] initWithStartingColor:RGB(0xffffff,.8) endingColor:RGB(0xffffff,0)];
        [glow drawFromCenter:NSMakePoint(290,970) radius:0 toCenter:NSMakePoint(290,970) radius:850 options:0];
        [NSGraphicsContext restoreGraphicsState];
        NSBezierPath *rim=Round(NSMakeRect(35,35,954,954),213);rim.lineWidth=3;[RGB(0xffffff,.22) setStroke];[rim stroke];
        NSBezierPath *shell=Round(NSMakeRect(188,337,602,350),80);
        [NSGraphicsContext saveGraphicsState];
        NSShadow *shadow=[NSShadow new];shadow.shadowColor=RGB(0x00291e,.35);shadow.shadowBlurRadius=35;shadow.shadowOffset=NSMakeSize(0,-18);[shadow set];
        [RGB(0x146349,1) setFill];[shell fill];
        [NSGraphicsContext restoreGraphicsState];
        NSGradient *glass=[[NSGradient alloc] initWithStartingColor:RGB(0x178661,1) endingColor:RGB(0x47be82,1)];
        [glass drawInBezierPath:shell angle:90];
        shell.lineWidth=4;[RGB(0x076647,.30) setStroke];[shell stroke];
        NSBezierPath *terminal=Round(NSMakeRect(815,447,28,130),13);[RGB(0x237c5b,1) setFill];[terminal fill];
        NSBezierPath *charge=Round(NSMakeRect(225,375,397,274),47);
        NSGradient *fill=[[NSGradient alloc] initWithStartingColor:RGB(0xe6fff0,.94) endingColor:RGB(0xf8fff7,.97)];
        [fill drawInBezierPath:charge angle:85];
        NSBezierPath *cap=Round(NSMakeRect(666,390,13,244),6.5);[RGB(0xf3fff7,.96) setFill];[cap fill];
        // The limit marker is integrated with the battery, with no floating detail.
        NSBezierPath *notch=Round(NSMakeRect(652,655,42,13),6.5);[RGB(0xf3fff7,.96) setFill];[notch fill];
        [NSGraphicsContext restoreGraphicsState];
        NSData *png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        NSString *name=[NSString stringWithFormat:@"chargecap-%ld.png",(long)size];
        if (![png writeToFile:[folder stringByAppendingPathComponent:name] atomically:YES])return 1;
    }
    return 0;
} }
