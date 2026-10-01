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
#import <execinfo.h>
#import <signal.h>
#import <string.h>
// Diagnostic v2 for the 6.85 account-menu crash: v1 (constructor-installed
// NSUncaughtExceptionHandler only) left the pasteboard empty, most likely
// because the host app's own crash reporter installs its handlers later and
// replaces ours, or because the crash is a signal rather than an NSException.
// This version installs both an uncaught-exception handler and signal handlers
// (SIGABRT/SIGSEGV/SIGBUS/SIGILL, chaining to any previous handler), re-arms
// them on a delay and right before the account menu builds, and copies the
// report to the pasteboard from any thread.
static void GSCrashReportToPasteboard(NSString *report){
 NSLog(@"%@",report);
 if(NSThread.isMainThread){UIPasteboard.generalPasteboard.string=report;return;}
 dispatch_sync(dispatch_get_main_queue(),^{UIPasteboard.generalPasteboard.string=report;});
}
static void GSUncaughtExceptionHandler(NSException *exception){
 @autoreleasepool{
  @try{
   NSMutableString *report=[NSMutableString stringWithFormat:@"Gunshot uncaught %@\nreason: %@\n",exception.name,exception.reason];
   NSArray *stack=exception.callStackSymbols;NSUInteger n=stack.count<16?stack.count:16;
   for(NSUInteger i=0;i<n;i++)[report appendFormat:@"%@\n",stack[i]];
   GSCrashReportToPasteboard(report);
  }@catch(id ignored){}
 }
}
static struct sigaction GSOldSignalHandlers[4];
static const int GSSignals[]={SIGABRT,SIGSEGV,SIGBUS,SIGILL};
static volatile sig_atomic_t GSSignalDepth=0;
static void GSSignalHandler(int sig){
 if(!GSSignalDepth){
  GSSignalDepth=1;
  void *frames[32];int n=backtrace(frames,32);
  char **syms=backtrace_symbols(frames,n);
  NSMutableString *report=[NSMutableString stringWithFormat:@"Gunshot signal %d\n",sig];
  for(int i=0;i<n&&i<16;i++)[report appendFormat:@"%s\n",syms?syms[i]:"?"];
  free(syms);
  GSCrashReportToPasteboard(report);
  GSSignalDepth=0;
 }
 int idx=-1;for(int i=0;i<4;i++)if(GSSignals[i]==sig)idx=i;
 if(idx>=0){
  struct sigaction *old=&GSOldSignalHandlers[idx];
  if(old->sa_handler!=SIG_DFL&&old->sa_handler!=SIG_IGN&&old->sa_handler!=&GSSignalHandler){
   if(old->sa_flags&SA_SIGINFO)((void(*)(int,siginfo_t*,void*))old->sa_sigaction)(sig,NULL,NULL);
   else old->sa_handler(sig);
   return;
  }
 }
 signal(sig,SIG_DFL);raise(sig);
}
// Non-static: re-armed from the account-menu hook right before the menu builds,
// so this is the last handler installed even if the host app installs its own.
void GSReinstallCrashCatcher(void){
 @autoreleasepool{
  @try{
   NSSetUncaughtExceptionHandler(&GSUncaughtExceptionHandler);
   for(int i=0;i<4;i++){
    struct sigaction cur;memset(&cur,0,sizeof(cur));
    // Idempotent: never overwrite the saved previous handler with ourselves,
    // or the signal handler would chain into itself forever.
    if(sigaction(GSSignals[i],NULL,&cur)==0&&cur.sa_handler==&GSSignalHandler)continue;
    struct sigaction sa;memset(&sa,0,sizeof(sa));
    sa.sa_handler=&GSSignalHandler;sigemptyset(&sa.sa_mask);sa.sa_flags=0;
    sigaction(GSSignals[i],&sa,&GSOldSignalHandlers[i]);
   }
  }@catch(id ignored){}
 }
}
__attribute__((constructor)) static void GSLoadJailed(void) {
 @autoreleasepool {
 GSReinstallCrashCatcher();
 // The host app's own crash reporter may install its handlers after ours;
 // re-arm late so we stay the last handler installed.
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{GSReinstallCrashCatcher();});
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(15*NSEC_PER_SEC)),dispatch_get_main_queue(),^{GSReinstallCrashCatcher();});
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
