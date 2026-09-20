#import "../Shared/GSPhotosCompatibility.h"
#import "../Shared/GSLocalization.h"
#import "GSAccountMenu.h"
#import "GSPanel.h"
#import "GSNativeAccount.h"
#import "GSUnlimitedStorage.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>

// Google Photos 6.85 moved the custom account-menu item from the older
// OGLAccountMenuCustomItem class to GIKAccountMenuCustomItem and removed the
// itemType initializer.  Keep the 6.85 ABI completely separate from the
// audited 7.x implementation below.
static char GSMenuMarker;
static void (*GSUIAction)(id,SEL,NSInteger,id,id);
static NSUInteger (*GSSections)(id,SEL,id);
static NSUInteger (*GSItems)(id,SEL,id,NSUInteger);
static id (*GSItem)(id,SEL,id,NSIndexPath *);
static void (*GSAction)(id,SEL,id,NSIndexPath *);
static BOOL GSMenuLegacy685;

static NSUInteger GSSection(id object,id controller){
 return GSSections(object,NSSelectorFromString(@"numberOfCustomSectionsForAccountMenuViewController:"),controller);
}
static NSUInteger GSMenuSections(id object,SEL selector,id controller){
 return GSSections(object,selector,controller)+1;
}
static NSUInteger GSMenuItems(id object,SEL selector,id controller,NSUInteger section){
 return section==GSSection(object,controller)?1:GSItems(object,selector,controller,section);
}
static BOOL GSOwnItem(id object,id controller,NSIndexPath *path){
 return path.section==GSSection(object,controller)&&path.row==0;
}

static id GSMenuItem(id object,SEL selector,id controller,NSIndexPath *path){
 if(!GSOwnItem(object,controller))return GSItem(object,selector,controller,path);
 Class itemClass=NSClassFromString(GSMenuLegacy685?@"GIKAccountMenuCustomItem":@"OGLAccountMenuCustomItem");
 id item=nil;
 if(GSMenuLegacy685){
  item=[[itemClass alloc]initWithTitle:GSL(@"GoToHP settings") icon:[UIImage systemImageNamed:@"gearshape"]];
 }else{
  item=[[itemClass alloc]initWithTitle:GSL(@"GoToHP settings") icon:[UIImage systemImageNamed:@"gearshape"] itemType:1];
 }
 if(item)objc_setAssociatedObject(item,&GSMenuMarker,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 return item;
}
static void GSMenuAction(id object,SEL selector,id controller,NSIndexPath *path){
 if(!GSOwnItem(object,controller)){GSAction(object,selector,controller,path);return;}
 GSPresentSettings([controller isKindOfClass:UIViewController.class]?controller:nil);
}
static id GSMenuGet(id object,NSString *name){
 if(!object)return nil;
 SEL selector=NSSelectorFromString(name);
 Method method=class_getInstanceMethod(object_getClass(object),selector);
 if(!method||strcmp(method_getTypeEncoding(method),"@16@0:8"))return nil;
 return ((id(*)(id,SEL))objc_msgSend)(object,selector);
}
static void GSMenuUIAction(id object,SEL selector,NSInteger type,id path,id controller){
 // 7.x only. 6.85 has no OGLAccountMenuUIEventHandler in its headers and
 // therefore never installs this pre-dismiss hook.
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
 if(!cls)return;
 NSArray *selectors=@[@"numberOfCustomSectionsForAccountMenuViewController:",@"accountMenuViewController:numberOfCustomItemsInSectionAtIndex:",@"accountMenuViewController:customItemAtIndexPath:",@"accountMenuViewController:performActionAtIndexPath:"];
 const char *encodings[]={"Q24@0:8@16","Q32@0:8@16Q24","@32@0:8@16@24","v32@0:8@16@24"};
 Method methods[4];
 for(NSUInteger i=0;i<4;i++){
  methods[i]=class_getInstanceMethod(cls,NSSelectorFromString(selectors[i]));
  if(!methods[i]||strcmp(method_getTypeEncoding(methods[i]),encodings[i]))return;
 }

 // 6.85: GIKAccountMenuCustomItem(initWithTitle:icon:) -> @32@0:8@16@24
 Class gikItem=NSClassFromString(@"GIKAccountMenuCustomItem");
 Method gikInit=class_getInstanceMethod(gikItem,@selector(initWithTitle:icon:));
 if(gikInit&& !strcmp(method_getTypeEncoding(gikInit),"@32@0:8@16@24")){
  GSMenuLegacy685=YES;
 }else{
  // Audited 7.x path: OGLAccountMenuCustomItem(initWithTitle:icon:itemType:)
  Class oglItem=NSClassFromString(@"OGLAccountMenuCustomItem");
  Method oglInit=class_getInstanceMethod(oglItem,@selector(initWithTitle:icon:itemType:));
  if(!oglInit||strcmp(method_getTypeEncoding(oglInit),"@40@0:8@16@24q32"))return;
  GSMenuLegacy685=NO;
 }

 GSSections=(void *)method_setImplementation(methods[0],(IMP)GSMenuSections);
 GSItems=(void *)method_setImplementation(methods[1],(IMP)GSMenuItems);
 GSItem=(void *)method_setImplementation(methods[2],(IMP)GSMenuItem);
 GSAction=(void *)method_setImplementation(methods[3],(IMP)GSMenuAction);

 // Optional 7.x pre-dismiss hook. Never installed on 6.85.
 if(!GSMenuLegacy685){
  Class handler=NSClassFromString(@"OGLAccountMenuUIEventHandler");
  Method action=class_getInstanceMethod(handler,NSSelectorFromString(@"performCustomActionType:indexPath:accountMenuViewController:"));
  if(action&&!strcmp(method_getTypeEncoding(action),"v40@0:8q16@24@32"))
   GSUIAction=(void *)method_setImplementation(action,(IMP)GSMenuUIAction);
 }
 installed=YES;
 GSInstallNativeAccount();
}
