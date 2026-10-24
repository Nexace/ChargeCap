#import "charge.h"
#include <assert.h>

@interface TestClient : NSObject
@property unsigned char value;
@property NSArray *limits;
@property BOOL rejectWrite;
@property BOOL ignoreWrite;
@property NSError *readError;
@property NSError *availableError;
@property NSInteger writes;
@property NSUInteger optimizedState;
@property BOOL rejectOptimized;
@property BOOL ignoreOptimized;
@end
@implementation TestClient
- (NSUInteger)isSmartChargingCurrentlyEnabled:(NSError **)error { *error=self.readError;return self.optimizedState; }
- (BOOL)enableSmartCharging:(NSError **)error { (void)error;if(self.rejectOptimized)return NO;if(!self.ignoreOptimized)self.optimizedState=1;return YES; }
- (BOOL)disableSmartCharging:(NSError **)error { (void)error;if(self.rejectOptimized)return NO;if(!self.ignoreOptimized)self.optimizedState=0;return YES; }
- (unsigned char)getMCLLimitWithError:(NSError **)error { *error = self.readError; return self.value; }
- (NSArray *)availableChargeLimitsWithError:(NSError **)error { *error = self.availableError; return self.limits; }
- (BOOL)setMCLLimit:(unsigned char)value error:(NSError **)error {
    (void)error;
    self.writes++;
    if (self.rejectWrite) return NO;
    if (!self.ignoreWrite) self.value = value;
    return YES;
}
@end

int main(void) { @autoreleasepool {
    for (NSInteger n = -100; n <= 200; n++)
        assert(ValidLimit(n) == (n == 80 || n == 85 || n == 90 || n == 95 || n == 100));
    TestClient *client = [TestClient new];
    client.limits = @[@80, @85, @90, @95, @100]; client.value = 85;
    for (NSNumber *n in client.limits) assert(WriteLimit(client, n.integerValue) == nil);
    NSInteger count = client.writes;
    assert(WriteLimit(client, 81) && client.writes == count);
    client.limits = @[@80];
    assert(WriteLimit(client, 90) && client.writes == count);
    client.availableError = [NSError errorWithDomain:@"Test" code:1 userInfo:nil];
    assert(WriteLimit(client, 80) && client.writes == count);
    client.availableError = nil; client.limits = @[@80, @85, @90, @95, @100];
    client.rejectWrite = YES;
    assert(WriteLimit(client, 80));
    client.rejectWrite = NO; client.ignoreWrite = YES; client.value = 85;
    assert(WriteLimit(client, 90)); // A reported success without readback is a failure.
    client.ignoreWrite = NO;
    client.readError = [NSError errorWithDomain:@"Test" code:2 userInfo:nil];
    assert(WriteLimit(client, 90));
    NSInteger value = -1;
    assert(ReadLimit(client, &value) && value == -1);
    client.readError = nil; client.value = 0;
    assert(ReadLimit(client, &value) && value == -1);
    assert(ReadLimit(nil, &value) && WriteLimit(nil, 80));
    assert(HasMethod([TestClient class], @selector(getMCLLimitWithError:), "C24@0:8^@16"));
    assert(!HasMethod([TestClient class], @selector(getMCLLimitWithError:), "Q24@0:8^@16"));
    assert(!WriteOptimized(client,YES) && client.optimizedState==1);
    assert(!WriteOptimized(client,NO) && client.optimizedState==0);
    client.rejectOptimized=YES;assert(WriteOptimized(client,YES));client.rejectOptimized=NO;
    client.ignoreOptimized=YES;assert(WriteOptimized(client,YES));client.ignoreOptimized=NO;
    client.optimizedState=2;BOOL optimized=NO;assert(ReadOptimized(client,&optimized));
    assert(ReadOptimized(nil,&optimized) && WriteOptimized(nil,YES));
    // Validate the dynamic factory as well without contacting the service.
    NSError *error = nil;
    assert(ChargeClient(&error) != nil && error == nil);
    puts("PASS: allowed values, unavailable controls, daemon errors, write rejection, readback, and private ABI guards.");
    return 0;
} }
