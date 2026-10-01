#import "host_profile.h"
#import "../Shared/GSLocalization.h"
#import "../UI/GSAccountMenu.h"
#import "../UI/GSPanel.h"
#import <objc/runtime.h>
#include <assert.h>
@implementation UIViewController @end
@implementation UITableViewController @end
@implementation UIActivity @end
@implementation UIImage
+ (instancetype)systemImageNamed:(NSString *)name{return [self new];}
@end
@implementation NSIndexPath (GSMenuFixture)
- (NSInteger)section{return [self indexAtPosition:0];}
- (NSInteger)row{return [self indexAtPosition:1];}
+ (instancetype)indexPathForRow:(NSInteger)row inSection:(NSInteger)section{NSUInteger indices[]={section,row};return [self indexPathWithIndexes:indices length:2];}
@end
static NSUInteger opened,originalActions,dismissed,nativeInstalled;
static UIViewController *lastHost;
void GSPresentSettings(UIViewController *host){opened++;lastHost=host;}
void GSInstallUnlimitedStorage(void){}
void GSInstallNativeAccount(void){nativeInstalled++;}
static NSString *version=@"unsupported";
static BOOL host=NO;
@interface GSFixtureBundle : NSObject @end
@implementation GSFixtureBundle
- (id)objectForInfoDictionaryKey:(NSString *)key{return [key isEqual:@"CFBundleExecutable"]?(host?@"GooglePhotos":@"OtherApp"):version;}
@end
static id MainBundle(id object,SEL selector){static id bundle;if(!bundle)bundle=[GSFixtureBundle new];return bundle;}
@interface GIKAccountMenuCustomItem : NSObject
- (instancetype)initWithTitle:(id)title icon:(id)icon;
@property(nonatomic,copy) NSString *title;
@end
@implementation GIKAccountMenuCustomItem
- (instancetype)initWithTitle:(id)title icon:(id)icon{if((self=[super init])){self.title=title;}return self;}
@end
@interface PHSMyAccountMenuDataSource : NSObject
- (NSUInteger)numberOfCustomSectionsForAccountMenuViewController:(id)controller;
- (NSUInteger)accountMenuViewController:(id)controller numberOfCustomItemsInSectionAtIndex:(NSUInteger)section;
- (id)accountMenuViewController:(id)controller customItemAtIndexPath:(id)path;
- (void)accountMenuViewController:(id)controller performActionAtIndexPath:(id)path;
@end
@implementation PHSMyAccountMenuDataSource
- (NSUInteger)numberOfCustomSectionsForAccountMenuViewController:(id)controller{return 1;}
- (NSUInteger)accountMenuViewController:(id)controller numberOfCustomItemsInSectionAtIndex:(NSUInteger)section{return 3;}
- (id)accountMenuViewController:(id)controller customItemAtIndexPath:(id)path{return [[GIKAccountMenuCustomItem alloc]initWithTitle:@"Native item" icon:nil];}
- (void)accountMenuViewController:(id)controller performActionAtIndexPath:(id)path{originalActions++;}
@end
// Real code walks this session's dependency chain to identify the tagged item.
@interface GSFixtureNode : NSObject
@property(nonatomic,strong) id accountMenuPresenter;
@property(nonatomic,strong) id accountMenuDependencies;
@property(nonatomic,strong) id customItemsDataSource;
@end
@implementation GSFixtureNode @end
@interface GIKAccountMenuUIEventHandler : NSObject
@property(nonatomic,strong) id session;
- (void)performCustomActionType:(NSInteger)type indexPath:(id)path accountMenuViewController:(id)controller;
@end
@implementation GIKAccountMenuUIEventHandler
- (void)performCustomActionType:(NSInteger)type indexPath:(id)path accountMenuViewController:(id)controller{dismissed++;}
@end
int main(void){@autoreleasepool{
 method_setImplementation(class_getClassMethod(NSBundle.class,@selector(mainBundle)),(IMP)MainBundle);
 PHSMyAccountMenuDataSource *source=[PHSMyAccountMenuDataSource new];UIViewController *controller=[UIViewController new];
 GSInstallAccountMenu();assert([source numberOfCustomSectionsForAccountMenuViewController:controller]==1);
 host=YES;version=GSFixtureVersion;GSInstallAccountMenu();GSInstallAccountMenu();assert(nativeInstalled==1);
 assert([source numberOfCustomSectionsForAccountMenuViewController:controller]==2);
 assert([source accountMenuViewController:controller numberOfCustomItemsInSectionAtIndex:1]==1);
 assert([source accountMenuViewController:controller numberOfCustomItemsInSectionAtIndex:0]==3);
 NSIndexPath *own=[NSIndexPath indexPathForRow:0 inSection:1],*other=[NSIndexPath indexPathForRow:0 inSection:0];
 assert([[[source accountMenuViewController:controller customItemAtIndexPath:own]title]isEqual:GSL(@"GoToHP settings")]);
 GSFixtureNode *session=[GSFixtureNode new],*presenter=[GSFixtureNode new],*deps=[GSFixtureNode new];session.accountMenuPresenter=presenter;presenter.accountMenuDependencies=deps;deps.customItemsDataSource=source;
 GIKAccountMenuUIEventHandler *handler=[GIKAccountMenuUIEventHandler new];handler.session=session;
 [handler performCustomActionType:1 indexPath:own accountMenuViewController:controller];
 assert(opened==1&&dismissed==0&&lastHost==controller); // Intercept BEFORE native dismiss.
 [handler performCustomActionType:1 indexPath:other accountMenuViewController:controller];assert(opened==1&&dismissed==1);
 [source accountMenuViewController:controller performActionAtIndexPath:other];assert(originalActions==1);
 // A delegate wrapper / detached controller can use the active-window fallback.
 [source accountMenuViewController:[NSObject new] performActionAtIndexPath:own];assert(opened==2&&lastHost==nil);
 deps.customItemsDataSource=nil;[handler performCustomActionType:1 indexPath:own accountMenuViewController:controller];assert(dismissed==2&&opened==2);
 return 0;
}}
