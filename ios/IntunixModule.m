#import <React/RCTBridgeModule.h>
#import <React/RCTViewManager.h>

@interface RCT_EXTERN_MODULE(Intunix, NSObject)
RCT_EXTERN_METHOD(initialize:(NSString *)apiKey options:(NSDictionary *)options)
RCT_EXTERN_METHOD(identify:(NSString *)userId traits:(NSDictionary *)traits)
RCT_EXTERN_METHOD(reset)
RCT_EXTERN_METHOD(track:(NSString *)event properties:(NSDictionary *)properties)
RCT_EXTERN_METHOD(screen:(NSString *)name)
RCT_EXTERN_METHOD(setContext:(nullable NSDictionary *)context)
RCT_EXTERN_METHOD(showForm:(NSString *)form context:(nullable NSDictionary *)context)
RCT_EXTERN_METHOD(register:(NSString *)form)
RCT_EXTERN_METHOD(unregister:(NSString *)form)
RCT_EXTERN_METHOD(setTheme:(NSString *)theme)
@end

@interface RCT_EXTERN_MODULE(IntunixFormViewManager, RCTViewManager)
RCT_EXPORT_VIEW_PROPERTY(form, NSString)
RCT_EXPORT_VIEW_PROPERTY(formContext, NSDictionary)
RCT_EXPORT_VIEW_PROPERTY(theme, NSString)
RCT_EXPORT_VIEW_PROPERTY(onHeightChange, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onFinished, RCTDirectEventBlock)
@end
