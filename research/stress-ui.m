// Read-only visual exercise. No setting-change actions are sent.
#define main ChargeCapProductMain
#import "../src/main.m"
#undef main

@interface StressApp : ChargeApp
@end
@implementation StressApp
- (void)profileOpen {
    printf("Stress startup: %.3f MB\n",Footprint());fflush(stdout);
    if(getenv("CHARGECAP_STRESS_HINT_ONLY")) {
        self.hovering=YES;[self showHint:nil];[self.hintPanel displayIfNeeded];
        [self performSelector:@selector(profileReport) withObject:nil afterDelay:9];return;
    }
    [self profileCycle];
}
- (void)profileCycle {
    @autoreleasepool {
        if(self.cycle>=40) {
            [self hideHint];[self closePanel:nil];
            [self performSelector:@selector(profileReport) withObject:nil afterDelay:3];return;
        }
        if(self.cycle%2==0) {
            [self closePanel:nil];self.hovering=YES;[self showHint:nil];[self.hintPanel displayIfNeeded];
        } else {
            [self togglePanel:nil];
            self.view.slider.limit=80+5*((self.cycle/2)%5);
            self.view.optimized.hidden=self.view.slider.limit!=100;
            self.view.optimized.on=YES;
            [self.panel makeKeyWindow];[self.panel makeFirstResponder:self.view.slider];
            self.view.needsDisplay=YES;self.view.slider.needsDisplay=YES;self.view.optimized.needsDisplay=YES;
            [self.panel displayIfNeeded];
        }
        [self sample:nil];
        printf("Visual cycle %d: %.3f MB; lifetime peak %.3f MB\n",self.cycle,Footprint(),self.peak);fflush(stdout);
        self.cycle++;
        // Exercise both fast reopening and reopening after idle resources were released.
        if(self.cycle%10==0){[self hideHint];[self closePanel:nil];}
    }
    [self performSelector:@selector(profileCycle) withObject:nil afterDelay:self.cycle%10==0?3.2:.25];
}
- (void)profileReport {
    [self sample:nil];
    printf("Stress idle after cleanup: %.3f MB; kernel lifetime peak: %.3f MB\n",Footprint(),self.peak);fflush(stdout);
    [NSApp terminate:nil];
}
@end

int main(void) { @autoreleasepool {
    NSApplication *app=NSApplication.sharedApplication;
    [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
    StressApp *delegate=[StressApp new];delegate.profiling=YES;app.delegate=delegate;
    [app run];return 0;
} }
