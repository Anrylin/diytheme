// Tweak.xm —— DIY主题 v4（hook 最底层 imageNamed:inBundle:withConfiguration:）
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSString *gThemeRoot = nil;
static NSMutableDictionary *gThemeImages = nil;
static NSString *gLogPath = nil;

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

static NSString *ThemeRoot(void) {
    if (gThemeRoot) return gThemeRoot;
    gThemeRoot = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/DIYThemes"];
    [[NSFileManager defaultManager] createDirectoryAtPath:gThemeRoot withIntermediateDirectories:YES attributes:nil error:nil];
    return gThemeRoot;
}

static NSString *Norm(NSString *s) {
    if (!s) return nil;
    NSString *t = s;
    t = [t stringByReplacingOccurrencesOfString:@"@3x" withString:@""];
    t = [t stringByReplacingOccurrencesOfString:@"@2x" withString:@""];
    return [t stringByDeletingPathExtension];
}

static void LoadTheme(NSString *name) {
    @autoreleasepool {
        gThemeImages = [NSMutableDictionary dictionary];
        NSString *root = [ThemeRoot() stringByAppendingPathComponent:name];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSDirectoryEnumerator *en = [fm enumeratorAtPath:root];
        int n = 0;
        for (NSString *rel in en) {
            @autoreleasepool {
                NSString *full = [root stringByAppendingPathComponent:rel];
                BOOL isDir = NO;
                [fm fileExistsAtPath:full isDirectory:&isDir];
                if (isDir) continue;
                NSString *ext = rel.pathExtension.lowercaseString;
                if ([ext isEqualToString:@"png"] || [ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"]) {
                    UIImage *img = [UIImage imageWithContentsOfFile:full];
                    if (img) { gThemeImages[Norm(rel.lastPathComponent)] = img; n++; }
                }
            }
        }
        Log(@"加载主题 [%@] 共 %d 张图", name, n);
    }
}

static UIImage *ThemeImage(NSString *name) {
    if (!gThemeImages || !name || !name.length) return nil;
    return gThemeImages[Norm(name)];
}

// 最底层 hook
static IMP gOrigLow = NULL;
static UIImage *my_low(id self, SEL _cmd, NSString *name, NSBundle *bundle, id config) {
    UIImage *t = ThemeImage(name);
    if (t) return t;
    return ((UIImage *(*)(id, SEL, NSString *, NSBundle *, id))gOrigLow)(self, _cmd, name, bundle, config);
}

// 也 hook 高层 imageNamed:（双保险）
static IMP gOrigHigh = NULL;
static UIImage *my_high(id self, SEL _cmd, NSString *name) {
    UIImage *t = ThemeImage(name);
    if (t) return t;
    return ((UIImage *(*)(id, SEL, NSString *))gOrigHigh)(self, _cmd, name);
}

__attribute__((constructor))
static void Init(void) {
    @autoreleasepool {
        Log(@"===== DIY主题 v4 启动 =====");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
            dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                @autoreleasepool {
                    // hook 底层
                    Method ml = class_getClassMethod([UIImage class], @selector(imageNamed:inBundle:withConfiguration:));
                    if (ml && !gOrigLow) {
                        gOrigLow = method_getImplementation(ml);
                        method_setImplementation(ml, (IMP)my_low);
                        Log(@"已 hook imageNamed:inBundle:withConfiguration:");
                    }
                    // hook 高层
                    Method mh = class_getClassMethod([UIImage class], @selector(imageNamed:));
                    if (mh && !gOrigHigh) {
                        gOrigHigh = method_getImplementation(mh);
                        method_setImplementation(mh, (IMP)my_high);
                        Log(@"已 hook imageNamed:");
                    }
                    // 自动加载第一个主题
                    NSArray *dirs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:ThemeRoot() error:nil];
                    for (NSString *d in dirs) {
                        if ([d hasPrefix:@"."]) continue;
                        NSString *full = [ThemeRoot() stringByAppendingPathComponent:d];
                        BOOL isDir = NO;
                        if ([[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&isDir] && isDir) {
                            LoadTheme(d);
                            break;
                        }
                    }
                    Log(@"初始化完成");
                }
            });
    }
}
