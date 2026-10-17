// Tweak.xm —— DIY主题 v3（诊断版：hook 底层 imageNamed，抓微信实际请求的图片名）
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSString *gLogPath = nil;
static NSString *gNamesPath = nil;
static int gLogCount = 0;

static void Log(NSString *fmt, ...) {
    static FILE *fp = NULL;
    if (!gLogPath) gLogPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/diytheme_log.txt"];
    if (!fp) fp = fopen(gLogPath.UTF8String, "a");
    if (!fp) return;
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    fprintf(fp, "%s\n", s.UTF8String); fflush(fp);
}

// 记录微信请求的图片名（最多 800 条）
static void LogName(NSString *name, NSString *bundle) {
    if (gLogCount >= 800) return;
    gLogCount++;
    static FILE *fp = NULL;
    if (!gNamesPath) gNamesPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/diytheme_names.txt"];
    if (!fp) fp = fopen(gNamesPath.UTF8String, "a");
    if (!fp) return;
    fprintf(fp, "%s  [bundle=%s]\n", name.UTF8String ?: "(nil)", bundle ? bundle.UTF8String : "nil");
    if (gLogCount % 50 == 0) fflush(fp);
}

// 底层 hook：imageNamed:inBundle:compatibleWithTraitCollection:
static IMP gOrigLow = NULL;
static UIImage *my_low(id self, SEL _cmd, NSString *name, NSBundle *bundle, UITraitCollection *tc) {
    LogName(name, bundle.bundlePath);
    return ((UIImage *(*)(id, SEL, NSString *, NSBundle *, UITraitCollection *))gOrigLow)(self, _cmd, name, bundle, tc);
}

__attribute__((constructor))
static void Init(void) {
    @autoreleasepool {
        Log(@"===== DIY主题 v3 诊断版 启动 =====");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
            dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                @autoreleasepool {
                    Method m = class_getClassMethod([UIImage class],
                        @selector(imageNamed:inBundle:compatibleWithTraitCollection:));
                    if (m && !gOrigLow) {
                        gOrigLow = method_getImplementation(m);
                        method_setImplementation(m, (IMP)my_low);
                        Log(@"已 hook 底层 imageNamed:inBundle:compatibleWithTraitCollection:");
                    } else {
                        Log(@"没 hook 到（m=%p）", m);
                    }
                }
            });
    }
}
