#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "../UI/GSPanel.h"
#import "../UI/GSAccountMenu.h"
#import "../UI/GSNativeRouting.h"
#import "../UI/GSPhotosIntegration.h"
#import "../UI/GSAccountConnection.h"
#import "../UI/GSUploadMonitor.h"
#import "SideloadKeychain.h"
#import "SideloadIdentity.h"


// Independent Objective-C hooks: no Substrate / ElleKit dependency for IPA injection.
static id (*GSOriginalActivityInit)(id, SEL, NSArray *, NSArray *);
static id GSActivityInit(id object, SEL selector, NSArray *items, NSArray *activities) {
 NSMutableArray *all=activities?[activities mutableCopy]:[NSMutableArray array];
 GSUploadActivity *upload=[GSUploadActivity new];
 if([upload canPerformWithActivityItems:items])[all addObject:upload];
 return GSOriginalActivityInit(object,selector,items,all);
}
// Diagnostic for the 6.85 account-menu abort: copy the uncaught NSException's
// name/reason/stack to the pasteboard (and NSLog) before the process aborts,
// so the reason survives even when iOS writes no crash log.
static void GSUncaughtExceptionHandler(NSException *exception){
 @autoreleasepool{
  @try{
   NSMutableString *report=[NSMutableString stringWithFormat:@"Gunshot uncaught %@\nreason: %@\n",exception.name,exception.reason];
   NSArray *stack=exception.callStackSymbols;NSUInteger n=stack.count<16?stack.count:16;
   for(NSUInteger i=0;i<n;i++)[report appendFormat:@"%@\n",stack[i]];
   NSLog(@"%@",report);
   if(NSThread.isMainThread)UIPasteboard.generalPasteboard.string=report;
  }@catch(id ignored){}
 }
}
__attribute__((constructor)) static void GSLoadJailed(void) {
 @autoreleasepool {
 NSSetUncaughtExceptionHandler(&GSUncaughtExceptionHandler);
 GSInstallSideloadIdentity();
 GSInstallSideloadKeychain(); // SSO reads its Keychain mode during initialization.
 // LC's guest bundle is resolved lazily on the main queue, after guest setup.
 dispatch_async(dispatch_get_main_queue(),^{
 NSString *executable=[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"];
 if(![executable isEqualToString:@"GooglePhotos"])return;
 GSStartAccountConnection();
 [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){GSResumeAccountConnection();}];
 GSInstallAccountMenu();GSStartBackupIntegration();
 Method activity=class_getInstanceMethod(UIActivityViewController.class,@selector(initWithActivityItems:applicationActivities:));
 if(activity)GSOriginalActivityInit=(void *)method_setImplementation(activity,(IMP)GSActivityInit);
 });
 }
}
