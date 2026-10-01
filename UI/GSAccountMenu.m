#import "../Shared/GSPhotosCompatibility.h"
#import "../Shared/GSLocalization.h"
#import "GSAccountMenu.h"
#import "GSPanel.h"
#import "GSNativeAccount.h"
#import "GSUnlimitedStorage.h"
#import <objc/runtime.h>
#import <objc/message.h>

// Private declarations are version/ABI checked before any hook is installed.
@interface NSObject (GSMenuItemConstruction)
- (instancetype)initWithTitle:(NSString *)title icon:(UIImage *)icon itemType:(NSInteger)type;
- (instancetype)initWithTitle:(NSString *)title icon:(UIImage *)icon; // GIKAccountMenuCustomItem (Google Photos 6.85)
@end
static char GSMenuMarker;
// Resolved at install: OGLAccountMenuCustomItem (7.x) or GIKAccountMenuCustomItem (6.85).
static Class GSMenuItemClass;
static BOOL GSMenuItemTyped; // YES when the initializer takes itemType:
static void (*GSUIAction)(id,SEL,NSInteger,id,id);
static NSUInteger (*GSSections)(id,SEL,id);
static NSUInteger (*GSItems)(id,SEL,id,NSUInteger);
static id (*GSItem)(id,SEL,id,NSIndexPath *);
static void (*GSAction)(id,SEL,id,NSIndexPath *);
static NSUInteger GSSection(id object,id controller){return GSSections(object,NSSelectorFromString(@"numberOfCustomSectionsForAccountMenuViewController:"),controller);}
static NSUInteger GSMenuSections(id object,SEL selector,id controller){
// Our settings row is appended to the last native section instead of adding a
// new section: Google's accessory-view service reads section data through a
// path that bypasses these hooks and crashes on an unfamiliar section index.
NSUInteger n=GSSections(object,selector,controller);return n==0?1:n;}
static NSUInteger GSMenuItems(id object,SEL selector,id controller,NSUInteger section){
NSUInteger n=GSSections(object,NSSelectorFromString(@"numberOfCustomSectionsForAccountMenuViewController:"),controller);
if(n==0)return section==0?1:GSItems(object,selector,controller,section);
if(section==n-1)return GSItems(object,selector,controller,section)+1;return GSItems(object,selector,controller,section);}
return GSItems(object,selector,controller,section);}
static BOOL GSOwnItem(id object,id controller,NSIndexPath *path){
NSUInteger n=GSSection(object,controller);
if(n==0)return path.section==0&&path.row==0;
if(path.section!=n-1)return NO;
NSUInteger orig=GSItems(object,NSSelectorFromString(@"accountMenuViewController:numberOfCustomItemsInSectionAtIndex:"),controller,n-1);
return path.row==orig;}
static id GSMenuItem(id object,SEL selector,id controller,NSIndexPath *path){
 if(!GSOwnItem(object,controller,path))return GSItem(object,selector,controller,path);
 id item;
 if(GSMenuItemTyped){
  // itemType 1 is the native custom-action row, verified at 0x100c0ca10.
  item=[[GSMenuItemClass alloc]initWithTitle:GSL(@"GoToHP settings") icon:[UIImage systemImageNamed:@"gearshape"] itemType:1];
 }else{
  // Google Photos 6.85 (GIKAccountMenuCustomItem) has no itemType: parameter.
  item=[[GSMenuItemClass alloc]initWithTitle:GSL(@"GoToHP settings") icon:[UIImage systemImageNamed:@"gearshape"]];
 }
 objc_setAssociatedObject(item,&GSMenuMarker,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 return item;
}
static void GSMenuAction(id object,SEL selector,id controller,NSIndexPath *path){
 if(!GSOwnItem(object,controller,path)){GSAction(object,selector,controller,path);return;}
 GSPresentSettings([controller isKindOfClass:UIViewController.class]?controller:nil);
}
static id GSMenuGet(id object,NSString *name){
 SEL selector=NSSelectorFromString(name);Method method=class_getInstanceMethod(object_getClass(object),selector);
 if(!method||strcmp(method_getTypeEncoding(method),"@16@0:8"))return nil;
 return ((id(*)(id,SEL))objc_msgSend)(object,selector);
}
static void GSMenuUIAction(id object,SEL selector,NSInteger type,id path,id controller){
 // The native implementation dismisses the menu BEFORE invoking its delegate.
 // Identify our item through this session's data source, not a global row number.
 id item=nil;
 @try {
  id session=GSMenuGet(object,@"session");
  id presenter=GSMenuGet(session,@"accountMenuPresenter");
  id deps=GSMenuGet(presenter,@"accountMenuDependencies");
  id source=GSMenuGet(deps,@"customItemsDataSource");
  SEL itemSelector=NSSelectorFromString(@"accountMenuViewController:customItemAtIndexPath:");
  Method method=class_getInstanceMethod(object_getClass(source),itemSelector);
  if([path isKindOfClass:NSIndexPath.class]&&method&&!strcmp(method_getTypeEncoding(method),"@32@0:8@16@24"))
   item=((id(*)(id,SEL,id,id))objc_msgSend)(source,itemSelector,controller,path);
 }@catch(NSException *exception){item=nil;}
 if([objc_getAssociatedObject(item,&GSMenuMarker)boolValue]){
  GSPresentSettings([controller isKindOfClass:UIViewController.class]?controller:nil);return;
 }
 GSUIAction(object,selector,type,path,controller);
}
void GSInstallAccountMenu(void){
 GSInstallUnlimitedStorage();
 static BOOL installed;
 if(installed||![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"]isEqual:@"GooglePhotos"]||!GSPhotosHostSupported())return;
 Class cls=NSClassFromString(@"PHSMyAccountMenuDataSource");
 NSArray *selectors=@[@"numberOfCustomSectionsForAccountMenuViewController:",@"accountMenuViewController:numberOfCustomItemsInSectionAtIndex:",@"accountMenuViewController:customItemAtIndexPath:",@"accountMenuViewController:performActionAtIndexPath:"];
 const char *encodings[]={"Q24@0:8@16","Q32@0:8@16Q24","@32@0:8@16@24","v32@0:8@16@24"};Method methods[4];
 for(NSUInteger i=0;i<4;i++){methods[i]=class_getInstanceMethod(cls,NSSelectorFromString(selectors[i]));if(!methods[i]||strcmp(method_getTypeEncoding(methods[i]),encodings[i]))return;}
 // Custom-item class: OGLAccountMenuCustomItem -initWithTitle:icon:itemType: on 7.x,
 // GIKAccountMenuCustomItem -initWithTitle:icon: on Google Photos 6.85.
 Class itemClass=NSClassFromString(@"OGLAccountMenuCustomItem");
 Method init=class_getInstanceMethod(itemClass,@selector(initWithTitle:icon:itemType:));
 if(init&&!strcmp(method_getTypeEncoding(init),"@40@0:8@16@24q32")){GSMenuItemClass=itemClass;GSMenuItemTyped=YES;}
 else{
  itemClass=NSClassFromString(@"GIKAccountMenuCustomItem");
  init=class_getInstanceMethod(itemClass,@selector(initWithTitle:icon:));
  if(!init||strcmp(method_getTypeEncoding(init),"@32@0:8@16@24"))return;
  GSMenuItemClass=itemClass;GSMenuItemTyped=NO;
 }
 GSSections=(void *)method_setImplementation(methods[0],(IMP)GSMenuSections);
 GSItems=(void *)method_setImplementation(methods[1],(IMP)GSMenuItems);
 GSItem=(void *)method_setImplementation(methods[2],(IMP)GSMenuItem);
 GSAction=(void *)method_setImplementation(methods[3],(IMP)GSMenuAction);
 // Optional pre-dismiss hook; the delegate remains a fallback for other routes.
 Class handler=NSClassFromString(@"OGLAccountMenuUIEventHandler");
 if(!handler)handler=NSClassFromString(@"GIKAccountMenuUIEventHandler"); // Google Photos 6.85
 Method action=class_getInstanceMethod(handler,NSSelectorFromString(@"performCustomActionType:indexPath:accountMenuViewController:"));
 if(action&&!strcmp(method_getTypeEncoding(action),"v40@0:8q16@24@32"))GSUIAction=(void *)method_setImplementation(action,(IMP)GSMenuUIAction);
 installed=YES;GSInstallNativeAccount();
}
