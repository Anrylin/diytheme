// Tweak.xm —— DIY主题 v1
// 在微信里加一个「DIY主题」入口，扫描 Documents/DIYThemes/ 下的主题文件夹，一键应用
// 应用原理：hook +[UIImage imageNamed:]，微信要加载的资源名如果主题里有同名图，就替换

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ---------------- 全局状态 ----------------
static NSString *gThemeRoot = nil;
static NSMutableDictionary *gThemeImages = nil;   // 文件名(去@2x/@3x/.png) -> UIImage
static NSDictionary *gThemeConfig = nil;
static NSString *gCurrentTheme = nil;
static NSString *gLogPath = nil;

// ---------------- 日志 ----------------
static void Log(NSString *fmt, ...) {
    static FILE *fp = NULL;
    if (!gLogPath) {
        gLogPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/diytheme_log.txt"];
    }
    if (!fp) fp = fopen(gLogPath.UTF8String, "a");
    if (!fp) return;
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    fprintf(fp, "%s\n", s.UTF8String);
    fflush(fp);
}

// ---------------- 主题目录 ----------------
static NSString *ThemeRoot(void) {
    if (gThemeRoot) return gThemeRoot;
    gThemeRoot = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/DIYThemes"];
    [[NSFileManager defaultManager] createDirectoryAtPath:gThemeRoot withIntermediateDirectories:YES attributes:nil error:nil];
    return gThemeRoot;
}

// 列出所有主题（目录名）
static NSArray *ListThemes(void) {
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:ThemeRoot() error:nil];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *n in names) {
        if ([n hasPrefix:@"."]) continue;
        NSString *full = [ThemeRoot() stringByAppendingPathComponent:n];
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&isDir] && isDir)
            [out addObject:n];
    }
    return [out sortedArrayUsingSelector:@selector(compare:)];
}

// 归一化图片名：去掉 @2x/@3x 和 .png/.jpg 后缀
static NSString *Norm(NSString *s) {
    NSString *t = s;
    t = [t stringByReplacingOccurrencesOfString:@"@3x" withString:@""];
    t = [t stringByReplacingOccurrencesOfString:@"@2x" withString:@""];
    t = [t stringByDeletingPathExtension];
    return t;
}

// 加载主题：递归扫描文件夹，把图片塞进 gThemeImages
static void LoadTheme(NSString *name) {
    gCurrentTheme = name;
    gThemeImages = [NSMutableDictionary dictionary];
    gThemeConfig = nil;
    NSString *root = [ThemeRoot() stringByAppendingPathComponent:name];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *en = [fm enumeratorAtPath:root];
    int nimg = 0;
    for (NSString *rel in en) {
        NSString *full = [root stringByAppendingPathComponent:rel];
        BOOL isDir = NO;
        [fm fileExistsAtPath:full isDirectory:&isDir];
        if (isDir) continue;
        NSString *ext = rel.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"png"] || [ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"]) {
            UIImage *img = [UIImage imageWithContentsOfFile:full];
            if (img) {
                gThemeImages[Norm(rel.lastPathComponent)] = img;
                nimg++;
            }
        } else if ([rel.lastPathComponent isEqualToString:@"config.json"]) {
            NSData *d = [NSData dataWithContentsOfFile:full];
            gThemeConfig = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
        }
    }
    Log(@"已加载主题 [%@] 共 %d 张图, config=%@", name, nimg, gThemeConfig ? @"有" : @"无");
}

// 按资源名查主题图
static UIImage *ThemeImage(NSString *name) {
    if (!gThemeImages || !name || !name.length) return nil;
    UIImage *img = gThemeImages[Norm(name)];
    if (img) return img;
    // 兜底：去掉扩展名后匹配
    img = gThemeImages[[Norm(name) stringByDeletingPathExtension]];
    return img;
}

// ---------------- hook +[UIImage imageNamed:] ----------------
static IMP gOrigImageNamed = NULL;

static UIImage *my_imageNamed(id self, SEL _cmd, NSString *name) {
    UIImage *t = ThemeImage(name);
    if (t) return t;
    return ((UIImage *(*)(id, SEL, NSString *))gOrigImageNamed)(self, _cmd, name);
}

static void InstallImageHook(void) {
    Method m = class_getClassMethod([UIImage class], @selector(imageNamed:));
    if (m && !gOrigImageNamed) {
        gOrigImageNamed = method_getImplementation(m);
        method_setImplementation(m, (IMP)my_imageNamed);
        Log(@"已 hook +[UIImage imageNamed:]");
    }
}

// ---------------- 主题列表 UI ----------------
@interface DIYThemeListVC : UITableViewController
@end
@implementation DIYThemeListVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"DIY主题";
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"c"];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭"
        style:UIBarButtonItemStylePlain target:self action:@selector(close)];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return ListThemes().count; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"c" forIndexPath:ip];
    NSArray *themes = ListThemes();
    NSString *name = themes[ip.row];
    c.textLabel.text = name;
    c.accessoryType = [name isEqualToString:gCurrentTheme] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return c;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSString *name = ListThemes()[ip.row];
    LoadTheme(name);
    [tv reloadData];
    Log(@"应用主题: %@", name);
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"已应用"
        message:[NSString stringWithFormat:@"主题 [%@] 已应用\n建议重启微信让所有界面完全生效", name]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
@end

// 弹出主题列表（找一个当前顶层 VC 来 present）
static void ShowThemeList(void) {
    DIYThemeListVC *vc = [DIYThemeListVC new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    // 找当前 window 的 root 或最顶层 VC
    UIWindow *w = nil;
    for (UIWindow *x in [UIApplication sharedApplication].windows)
        if (x.isKeyWindow || x.windowLevel == UIWindowLevelNormal) { w = x; break; }
    if (!w) w = [UIApplication sharedApplication].keyWindow;
    UIViewController *top = w.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if ([top isKindOfClass:[UINavigationController class]])
        top = ((UINavigationController *)top).topViewController;
    [top presentViewController:nav animated:YES completion:nil];
    Log(@"已弹出主题列表");
}

// ---------------- 微信设置入口 ----------------
// 运行时找微信的设置页 VC，加一个「DIY主题」入口
static void InstallEntry(void) {
    unsigned int ncls = 0;
    Class *cls = objc_copyClassList(&ncls);
    for (unsigned int i = 0; i < ncls; i++) {
        Class c = cls[i];
        NSString *cn = NSStringFromClass(c);
        if (![cn containsString:@"Setting"] && ![cn containsString:@"More"]) continue;
        if (![c isSubclassOfClass:[UIViewController class]]) continue;
        // 找到设置页，hook viewDidAppear 加一个悬浮入口按钮
        SEL sel = @selector(viewDidAppear:);
        if (![c instancesRespondToSelector:sel]) continue;
        // 只 hook 第一个匹配的
        Method m = class_getInstanceMethod(c, sel);
        IMP orig = method_getImplementation(m);
        __block IMP o = orig;
        IMP r = imp_implementationWithBlock(^void(id self, BOOL anim) {
            ((void(*)(id, SEL, BOOL))o)(self, sel, anim);
            // 加悬浮按钮（只加一次）
            static BOOL added = NO;
            if (!added && [self isKindOfClass:[UIViewController class]]) {
                added = YES;
                dispatch_async(dispatch_get_main_queue(), ^{
                    @try {
                        UIViewController *vc = (UIViewController *)self;
                        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
                        [btn setTitle:@"🎨 DIY主题" forState:UIControlStateNormal];
                        btn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
                        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
                        btn.layer.cornerRadius = 16;
                        btn.frame = CGRectMake(0, 0, 120, 36);
                        [btn addTarget:btn action:@selector(_diyTapped) forControlEvents:UIControlEventTouchUpInside];
                        // 挂到导航栏右侧
                        if (vc.navigationController && vc.navigationItem) {
                            vc.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:btn];
                            Log(@"已在设置页加 DIY 入口按钮 -[%@]", NSStringFromClass(c));
                        }
                    } @catch (NSException *e) { Log(@"加入口异常 %@", e); }
                });
            }
        });
        method_setImplementation(m, r);
        Log(@"hook 设置页 viewDidAppear -[%@]", cn);
        free(cls);
        return;
    }
    free(cls);
    Log(@"没找到设置页类");
}

// 给 UIButton 加一个点击方法
@interface UIButton (DIY)
- (void)_diyTapped;
@end
@implementation UIButton (DIY)
- (void)_diyTapped { ShowThemeList(); }
@end

// ---------------- 构造 ----------------
__attribute__((constructor))
static void Init(void) {
    @autoreleasepool {
        Log(@"===== DIY主题 v1 启动 =====");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
            dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                @autoreleasepool {
                    InstallImageHook();
                    InstallEntry();
                    Log(@"初始化完成，主题目录 %@", ThemeRoot());
                }
            });
    }
}
