//
//  DOMainViewController.m
//  Dopamine
//
//  Created by tomt000 on 08/01/2024.
//

#import "DOMainViewController.h"
#import "DOUIManager.h"
#import "DOEnvironmentManager.h"
#import "DOJailbreaker.h"
#import "DOGlobalAppearance.h"
#import "DOActionMenuButton.h"
#import "DOUpdateViewController.h"
#import "DOLogCrashViewController.h"
#import "DOPSListController.h"
#import "DOThemeManager.h"
#import <pthread.h>
#import <sys/sysctl.h>
#import <libjailbreak/libjailbreak.h>

static NSString *DOWallpaperPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/dopamine-wallpaper.jpg"];
}

@interface DOWallpaperController : DOPSListController <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, copy) void (^changed)(void);
@end
@implementation DOWallpaperController
- (id)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [NSMutableArray array];
        PSSpecifier *header = [PSSpecifier emptyGroupSpecifier];
        [header setProperty:@"DOHeaderCell" forKey:@"headerCellClass"];
        [header setProperty:@"更换壁纸" forKey:@"title"];
        [items addObject:header];
        PSSpecifier *choose = [PSSpecifier preferenceSpecifierNamed:@"选择照片" target:self set:NULL get:NULL detail:nil cell:PSButtonCell edit:nil];
        choose.buttonAction = @selector(selectImage);
        [items addObject:choose];
        NSArray *titles = @[@"背景透明度", @"背景模糊度"];
        NSArray *keys = @[@"DOWallpaperOpacity", @"DOWallpaperBlur"];
        for (NSUInteger i = 0; i < titles.count; i++) {
            [items addObject:[PSSpecifier groupSpecifierWithName:titles[i]]];
            PSSpecifier *slider = [PSSpecifier preferenceSpecifierNamed:nil target:self set:@selector(setWallpaperValue:specifier:) get:@selector(wallpaperValue:) detail:nil cell:PSSliderCell edit:nil];
            [slider setProperty:keys[i] forKey:@"key"];
            [slider setProperty:@0 forKey:@"min"];
            [slider setProperty:@1 forKey:@"max"];
            [slider setProperty:@YES forKey:@"isContinuous"];
            [items addObject:slider];
        }
        [items addObject:[PSSpecifier emptyGroupSpecifier]];
        PSSpecifier *reset = [PSSpecifier preferenceSpecifierNamed:@"恢复默认背景" target:self set:NULL get:NULL detail:nil cell:PSButtonCell edit:nil];
        reset.buttonAction = @selector(resetImage);
        [items addObject:reset];
        _specifiers = items;
    }
    return _specifiers;
}
- (id)wallpaperValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    return [NSUserDefaults.standardUserDefaults objectForKey:key] ?: ([key isEqualToString:@"DOWallpaperOpacity"] ? @1 : @0);
}
- (void)setWallpaperValue:(NSNumber *)value specifier:(PSSpecifier *)specifier {
    [NSUserDefaults.standardUserDefaults setObject:value forKey:[specifier propertyForKey:@"key"]];
    if (self.changed) self.changed();
}
- (void)selectImage { UIImagePickerController *picker = [[UIImagePickerController alloc] init]; picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary; picker.delegate = self; [self presentViewController:picker animated:YES completion:nil]; }
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [picker dismissViewControllerAnimated:YES completion:nil]; }
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    [UIImageJPEGRepresentation(image, 0.9) writeToFile:DOWallpaperPath() atomically:YES];
    if (self.changed) self.changed(); [picker dismissViewControllerAnimated:YES completion:nil];
}
- (void)resetImage { [[NSFileManager defaultManager] removeItemAtPath:DOWallpaperPath() error:nil]; if (self.changed) self.changed(); }
@end

@interface DOMainViewController ()

@property DOJailbreakButton *jailbreakBtn;
@property NSArray<NSLayoutConstraint *> *jailbreakButtonConstraints;
@property DOActionMenuButton *updateButton;
@property(nonatomic) BOOL hideStatusBar;
@property(nonatomic) UIView *layoutView;
@property(nonatomic) UIButton *layoutStatusButton;
@property(nonatomic) UIImageView *wallpaperView;
@property(nonatomic) UIVisualEffectView *wallpaperBlur;
@property(nonatomic) BOOL hideHomeIndicator;

@end

@implementation DOMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupStack];
}

-(void)setupStack
{
    UIStackView *stackView = [[UIStackView alloc] init];
    [stackView setAxis:UILayoutConstraintAxisVertical];
    [stackView setAlignment:UIStackViewAlignmentTrailing];
    [stackView setDistribution:UIStackViewDistributionEqualSpacing];
    [stackView setTranslatesAutoresizingMaskIntoConstraints:NO];

    [self.view addSubview:stackView];


    int statusBarHeight = fmax(15, [[UIApplication sharedApplication] keyWindow].safeAreaInsets.top - 20);

    [NSLayoutConstraint activateConstraints:@[
        [stackView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:statusBarHeight],//-35
        [stackView.heightAnchor constraintEqualToAnchor:self.view.heightAnchor multiplier:[DOGlobalAppearance isHomeButtonDevice] ? 0.78 : 0.73]
    ]];

    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
        NSLayoutConstraint *relativeWidthConstraint = [stackView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.8];
        relativeWidthConstraint.priority = UILayoutPriorityDefaultHigh;
        NSLayoutConstraint *maxWidthConstraint = [stackView.widthAnchor constraintLessThanOrEqualToConstant:UI_IPAD_MAX_WIDTH];
        maxWidthConstraint.priority = UILayoutPriorityRequired;

        [NSLayoutConstraint activateConstraints:@[
            relativeWidthConstraint,
            maxWidthConstraint,
            [stackView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor]
        ]];
    }
    else
    {
        [NSLayoutConstraint activateConstraints:@[
            [stackView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:UI_PADDING],
            [stackView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-UI_PADDING],
        ]];
    }

    //Header
    DOHeaderView *headerView = [[DOHeaderView alloc] initWithImage: [UIImage imageNamed:@"Dopamine"] subtitles: @[
        [DOGlobalAppearance mainSubtitleString:[[DOEnvironmentManager sharedManager] versionSupportString]],
        [DOGlobalAppearance secondarySubtitleString:DOLocalizedString(@"Credits_Made_By")],
    ]];
    
    [stackView addArrangedSubview:headerView];

    [NSLayoutConstraint activateConstraints:@[
        [headerView.leadingAnchor constraintEqualToAnchor:stackView.leadingAnchor constant:5],
        [headerView.trailingAnchor constraintEqualToAnchor:stackView.trailingAnchor]
    ]];
    
    //Action Menu
    DOActionMenuView *actionView = [[DOActionMenuView alloc] initWithActions:@[
        [UIAction actionWithTitle:DOLocalizedString(@"Menu_Settings_Title") image:[UIImage systemImageNamed:@"gearshape" withConfiguration:[DOGlobalAppearance smallIconImageConfiguration]] identifier:@"settings" handler:^(__kindof UIAction * _Nonnull action) {
            [self.navigationController pushViewController:[[DOSettingsController alloc] init] animated:YES];
        }],
        [UIAction actionWithTitle:DOLocalizedString(@"Menu_Restart_SpringBoard_Title") image:[UIImage systemImageNamed:@"arrow.clockwise" withConfiguration:[DOGlobalAppearance smallIconImageConfiguration]] identifier:@"respring" handler:^(__kindof UIAction * _Nonnull action) {
            [self fadeToBlack:^{
                [[DOEnvironmentManager sharedManager] respring];
            }];
        }],
        [UIAction actionWithTitle:DOLocalizedString(@"Menu_Reboot_Userspace_Title") image:[UIImage systemImageNamed:@"arrow.clockwise.circle" withConfiguration:[DOGlobalAppearance smallIconImageConfiguration]] identifier:@"reboot-userspace" handler:^(__kindof UIAction * _Nonnull action) {
            [self fadeToBlack:^{
                [[DOEnvironmentManager sharedManager] rebootUserspace];
            }];
        }],
        [UIAction actionWithTitle:DOLocalizedString(@"Menu_Credits_Title") image:[UIImage systemImageNamed:@"info.circle" withConfiguration:[DOGlobalAppearance smallIconImageConfiguration]] identifier:@"credits" handler:^(__kindof UIAction * _Nonnull action) {
            [self.navigationController pushViewController:[[DOCreditsViewController alloc] init] animated:YES];
        }]
    ] delegate:self];
    
    [stackView addArrangedSubview: actionView];

    [NSLayoutConstraint activateConstraints:@[
        [actionView.leadingAnchor constraintEqualToAnchor:stackView.leadingAnchor],
        [actionView.trailingAnchor constraintEqualToAnchor:stackView.trailingAnchor],
    ]];
    
    
    UIView *buttonPlaceHolder = [[UIView alloc] init];
    [buttonPlaceHolder setTranslatesAutoresizingMaskIntoConstraints:NO];
    [stackView addArrangedSubview:buttonPlaceHolder];
    [NSLayoutConstraint activateConstraints:@[
        [buttonPlaceHolder.heightAnchor constraintEqualToConstant:60]
    ]];
    
    //Jailbreak Button
    BOOL isJailbroken = [[DOEnvironmentManager sharedManager] isJailbroken] || [[DOEnvironmentManager sharedManager] isJailbrokenWithOtherJailbreak];
    BOOL isSupported = [[DOEnvironmentManager sharedManager] isSupported];

    NSString *jailbreakButtonTitle = [self jailbreakButtonTitle];
        
    UIImage *jailbreakButtonImage;
    if (isSupported)
        jailbreakButtonImage = [UIImage systemImageNamed:@"lock.open" withConfiguration:[DOGlobalAppearance smallIconImageConfiguration]];
    else
        jailbreakButtonImage = [UIImage systemImageNamed:@"lock.slash" withConfiguration:[DOGlobalAppearance smallIconImageConfiguration]];
    
    self.jailbreakBtn = [[DOJailbreakButton alloc] initWithAction: [UIAction actionWithTitle:jailbreakButtonTitle image:jailbreakButtonImage identifier:@"jailbreak" handler:^(__kindof UIAction * _Nonnull action) {


/********************************** roothide specific ************************************/
        if(otherJailbreakActived(false)) {
            UIAlertController *alertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Error") message:DOLocalizedString(@"Your device currently has another jailbreak activated, please reboot device.") preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *rebootAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Close") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                //exit(0);
            }];
            [alertController addAction:rebootAction];
            [self presentViewController:alertController animated:YES completion:nil];
            return;
        }
/********************************** roothide specific ************************************/


        [actionView hide];
        [self.jailbreakBtn expandButton: self.jailbreakButtonConstraints];

        self.updateButton.userInteractionEnabled = NO;
        [UIView animateWithDuration:0.75 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:2.0  options: UIViewAnimationOptionCurveEaseInOut animations:^{
            [headerView setTransform:CGAffineTransformMakeTranslation(0, -25)];
            self.updateButton.alpha = 0;
        } completion:nil];
        
        [self startJailbreak];
        
    }]];
    self.jailbreakBtn.enabled = !isJailbroken && isSupported;
    if (isSupported) {
        stackView.hidden = YES;
        self.jailbreakBtn.hidden = YES;
        [self setupCustomLayoutWithActions:actionView.actions startAction:^{
            stackView.hidden = NO;
            self.jailbreakBtn.hidden = NO;
            self.layoutView.hidden = YES;
            [self.jailbreakBtn.button sendActionsForControlEvents:UIControlEventTouchUpInside];
        }];
    }

    [self.view addSubview:self.jailbreakBtn];

    [NSLayoutConstraint activateConstraints:(self.jailbreakButtonConstraints = @[
        [self.jailbreakBtn.leadingAnchor constraintEqualToAnchor:stackView.leadingAnchor],
        [self.jailbreakBtn.trailingAnchor constraintEqualToAnchor:stackView.trailingAnchor],
        [self.jailbreakBtn.heightAnchor constraintEqualToAnchor:buttonPlaceHolder.heightAnchor],
        [self.jailbreakBtn.centerYAnchor constraintEqualToAnchor:buttonPlaceHolder.centerYAnchor]
    ])];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        if ([[DOUIManager sharedInstance] environmentUpdateAvailable])
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setupUpdateAvailable:YES];
            });
        }
        else if ([[DOUIManager sharedInstance] isUpdateAvailable])
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setupUpdateAvailable:NO];
            });
        }
    });
}

- (void)refreshWallpaper {
    self.wallpaperView.image = [UIImage imageWithContentsOfFile:DOWallpaperPath()] ?: [[[DOThemeManager sharedInstance] enabledTheme] image];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id opacity = [defaults objectForKey:@"DOWallpaperOpacity"];
    self.wallpaperView.alpha = opacity ? [opacity floatValue] : 1;
    self.wallpaperBlur.alpha = [defaults floatForKey:@"DOWallpaperBlur"];
}

- (void)showWallpaperSettings {
    DOWallpaperController *controller = [[DOWallpaperController alloc] init];
    __weak typeof(self) weakSelf = self;
    controller.changed = ^{ [weakSelf refreshWallpaper]; };
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)setupCustomLayoutWithActions:(NSArray<UIAction *> *)actions startAction:(void (^)(void))startAction {
    UIView *page = [[UIView alloc] init]; page.translatesAutoresizingMaskIntoConstraints = NO; page.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1]; [self.view addSubview:page]; self.layoutView = page;
    [NSLayoutConstraint activateConstraints:@[[page.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor], [page.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor], [page.topAnchor constraintEqualToAnchor:self.view.topAnchor], [page.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]]];
    UIImageView *wallpaper = [[UIImageView alloc] init]; wallpaper.contentMode = UIViewContentModeScaleAspectFill; wallpaper.clipsToBounds = YES; wallpaper.translatesAutoresizingMaskIntoConstraints = NO; [page addSubview:wallpaper]; self.wallpaperView = wallpaper;
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]]; blur.translatesAutoresizingMaskIntoConstraints = NO; [page addSubview:blur]; self.wallpaperBlur = blur;
    UIView *shade = [[UIView alloc] init]; shade.backgroundColor = [UIColor colorWithWhite:0 alpha:0.28]; shade.translatesAutoresizingMaskIntoConstraints = NO; [page addSubview:shade];
    for (UIView *v in @[wallpaper, blur, shade]) [NSLayoutConstraint activateConstraints:@[[v.leadingAnchor constraintEqualToAnchor:page.leadingAnchor], [v.trailingAnchor constraintEqualToAnchor:page.trailingAnchor], [v.topAnchor constraintEqualToAnchor:page.topAnchor], [v.bottomAnchor constraintEqualToAnchor:page.bottomAnchor]]];
    [self refreshWallpaper];
    UILabel *title = [[UILabel alloc] init]; title.text = @"Dopamine"; title.font = [UIFont systemFontOfSize:36 weight:UIFontWeightSemibold]; title.textAlignment = NSTextAlignmentCenter; title.textColor = UIColor.whiteColor; title.translatesAutoresizingMaskIntoConstraints = NO; [page addSubview:title];
    UILabel *subtitle = [[UILabel alloc] init]; subtitle.text = [[DOEnvironmentManager sharedManager] versionSupportString]; subtitle.font = [UIFont systemFontOfSize:15]; subtitle.textColor = [UIColor colorWithWhite:1 alpha:0.8]; subtitle.textAlignment = NSTextAlignmentCenter; subtitle.translatesAutoresizingMaskIntoConstraints = NO; [page addSubview:subtitle];
    [NSLayoutConstraint activateConstraints:@[[title.centerXAnchor constraintEqualToAnchor:page.centerXAnchor], [title.centerYAnchor constraintEqualToAnchor:page.safeAreaLayoutGuide.topAnchor constant:70], [subtitle.centerXAnchor constraintEqualToAnchor:page.centerXAnchor], [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6]]];
    UIStackView *menu = [[UIStackView alloc] init]; menu.axis = UILayoutConstraintAxisVertical; menu.spacing = 0; menu.distribution = UIStackViewDistributionFillEqually; menu.translatesAutoresizingMaskIntoConstraints = NO; [page addSubview:menu];
    [NSLayoutConstraint activateConstraints:@[[menu.leadingAnchor constraintEqualToAnchor:page.safeAreaLayoutGuide.leadingAnchor constant:22], [menu.bottomAnchor constraintEqualToAnchor:page.safeAreaLayoutGuide.bottomAnchor constant:-28], [menu.widthAnchor constraintEqualToConstant:165], [menu.heightAnchor constraintEqualToConstant:288]]];
    UIAction *wall = [UIAction actionWithTitle:@"更换壁纸" image:nil identifier:nil handler:^(__kindof UIAction *a) { [self showWallpaperSettings]; }];
    BOOL jailbroken = !self.jailbreakBtn.enabled;
    NSString *statusTitle = jailbroken ? @"已经越狱" : [self jailbreakButtonTitle];
    if (!jailbroken && [statusTitle isEqualToString:DOLocalizedString(@"Button_Jailbreak_Title")]) statusTitle = @"去越狱";
    UIAction *status = [UIAction actionWithTitle:statusTitle image:nil identifier:nil handler:^(__kindof UIAction *a) { startAction(); }];
    NSArray *items = @[actions[1], actions[2], wall, actions[3], actions[0], status];
    NSArray *titles = @[@"刷新桌面", @"重启空间", @"更换壁纸", @"关于项目", @"应用设置", statusTitle];
    for (NSUInteger i=0; i<items.count; i++) {
        UIAction *action = items[i]; UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button addAction:action forControlEvents:UIControlEventTouchUpInside];
        UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration]; config.title = titles[i]; config.baseForegroundColor = UIColor.whiteColor; config.contentInsets = NSDirectionalEdgeInsetsMake(0, 4, 0, 4); button.configuration = config; button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        if (i == 1 || i == 0) button.enabled = [self actionMenuActionIsEnabled:action];
        if (i == 5) { button.userInteractionEnabled = !jailbroken; if (jailbroken) button.accessibilityTraits |= UIAccessibilityTraitNotEnabled; self.layoutStatusButton = button; }
        [menu addArrangedSubview:button];
    }
}

- (NSString *)jailbreakButtonTitle
{
    BOOL isJailbroken = [[DOEnvironmentManager sharedManager] isJailbroken];
    BOOL isSupported = [[DOEnvironmentManager sharedManager] isSupported];
    BOOL removeJailbreakEnabled = [[DOPreferenceManager sharedManager] boolPreferenceValueForKey:@"removeJailbreakEnabled" fallback:NO];

    NSString *jailbreakButtonTitle = DOLocalizedString(@"Button_Jailbreak_Title");
    if (!isSupported)
        jailbreakButtonTitle = DOLocalizedString(@"Unsupported");
    else if (isJailbroken)
        jailbreakButtonTitle = DOLocalizedString(@"Status_Title_Jailbroken");
    else if (removeJailbreakEnabled)
        jailbreakButtonTitle = DOLocalizedString(@"Button_Remove_Jailbreak");
    
    return jailbreakButtonTitle;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    NSString *title = [self jailbreakButtonTitle];
    [self.jailbreakBtn.button setTitle:title forState:UIControlStateNormal];
    if (self.layoutStatusButton) {
        if (!self.jailbreakBtn.enabled) title = @"已经越狱";
        else if ([title isEqualToString:DOLocalizedString(@"Button_Jailbreak_Title")]) title = @"去越狱";
        UIButtonConfiguration *configuration = self.layoutStatusButton.configuration;
        configuration.title = title;
        self.layoutStatusButton.configuration = configuration;
    }
}

- (void)startJailbreak
{
    DOJailbreaker *jailbreaker = [[DOJailbreaker alloc] init];

    [[DOUIManager sharedInstance] startLogCapture];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        if ([jailbreaker contiguousMappingWorkaroundNeeded]) {
            
            cpu_subtype_t cpuFamily = 0;
            size_t cpuFamilySize = sizeof(cpuFamily);
            sysctlbyname("hw.cpufamily", &cpuFamily, &cpuFamilySize, NULL, 0);
            NSString *workaroundMessage = DOLocalizedString(@"Respring_Required_Message");
            if (cpuFamily == CPUFAMILY_ARM_TYPHOON) {
                workaroundMessage = [workaroundMessage stringByAppendingString:[NSString stringWithFormat:@"\n\n%@", DOLocalizedString(@"Respring_Required_Notice_A8")]];
            }

            UIAlertController *contiguousMappingWorkaroundAlertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Respring_Required") message:workaroundMessage preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Respring_Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                exit(0);
            }];
            
            UIAlertAction *workaroundAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Apply_Workaround") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [jailbreaker applyContiguousMappingWorkaround];
            }];
            
            [contiguousMappingWorkaroundAlertController addAction:cancelAction];
            [contiguousMappingWorkaroundAlertController addAction:workaroundAction];
            contiguousMappingWorkaroundAlertController.preferredAction = workaroundAction;

            dispatch_async(dispatch_get_main_queue(), ^{
                [self presentViewController:contiguousMappingWorkaroundAlertController animated:YES completion:nil];
            });
            return;
        }

        //We need to get the preconfig mutex to start the jailbreak (self.jailbreakBtn.canStartJailbreak)
        [self.jailbreakBtn lockMutex];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.hideHomeIndicator = YES;
        });

        NSError *error;
        BOOL didRemove = NO;
        BOOL showLogs = YES;
        [jailbreaker runWithError:&error didRemoveJailbreak:&didRemove showLogs:&showLogs];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error && showLogs) {
                [[DOUIManager sharedInstance] sendLog:[NSString stringWithFormat:@"Jailbreak failed with error: %@", error] debug:NO];
                [self.navigationController pushViewController:[[DOLogCrashViewController alloc] initWithTitle:[error localizedDescription]] animated:YES];
            }
            else if (error && !showLogs) {
                // Used when there is an error that is explainable in such detail that additional logs are not needed
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Log_Error") message:[error localizedDescription] preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *rebootAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Reboot") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    exec_cmd_trusted(JBROOT_PATH("/sbin/reboot"), NULL);
                }];
                [alertController addAction:rebootAction];
                [self presentViewController:alertController animated:YES completion:nil];
            }
            else if (didRemove) {
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Removed_Jailbreak_Alert_Title") message:DOLocalizedString(@"Removed_Jailbreak_Alert_Message") preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *rebootAction = [UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Close") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    exit(0);
                }];
                [alertController addAction:rebootAction];
                [self presentViewController:alertController animated:YES completion:nil];
            }
            else {
                // No errors
                [[DOUIManager sharedInstance] completeJailbreak];
                [self fadeToBlack: ^{
                    [jailbreaker finalize];
                }];
            }
        });
        [self.jailbreakBtn unlockMutex];
    });
}

-(void)setupUpdateAvailable:(BOOL)environmentUpdate
{
    if (self.jailbreakBtn.didExpand)
        return;

    NSString *title = environmentUpdate ? DOLocalizedString(@"Button_Update_Environment") : DOLocalizedString(@"Button_Update_Available");
    
    NSString *releaseFrom = [[DOUIManager sharedInstance] getLaunchedReleaseTag];
    NSString *releaseTo = [[DOUIManager sharedInstance] getLatestReleaseTag];

    if (environmentUpdate)
    {
/************************************* roothide specfic ***********************************/
        releaseFrom = [[DOEnvironmentManager sharedManager] jailbrokenVersionRootHide];
/************************************* roothide specfic ***********************************/
        releaseTo = [[DOUIManager sharedInstance] getLaunchedReleaseTag];
    }

    self.updateButton = [DOActionMenuButton buttonWithAction:[UIAction actionWithTitle:title image:[UIImage systemImageNamed:@"arrow.down.circle" withConfiguration:[DOGlobalAppearance smallIconImageConfiguration]] identifier:@"update-available" handler:^(__kindof UIAction * _Nonnull action) {
        [self.navigationController pushViewController:[[DOUpdateViewController alloc] initFromTag:releaseFrom toTag:releaseTo] animated:YES];
    }] chevron:NO];

    self.updateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.updateButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.updateButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.updateButton.heightAnchor constraintEqualToConstant:30],
        [self.updateButton.bottomAnchor constraintEqualToAnchor:self.jailbreakBtn.topAnchor constant:[DOGlobalAppearance isHomeButtonDevice] ? -10 : -20]
    ]];

    [self.updateButton setTransform:CGAffineTransformMakeTranslation(0, 25)];
    [self.updateButton setAlpha:0];
    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:2.0  options: UIViewAnimationOptionCurveEaseInOut animations:^{
        [self.updateButton setTransform:CGAffineTransformIdentity];
        [self.updateButton setAlpha:1];
    } completion:nil];
}

-(void)simulateJailbreak
{
    // Let's simulate a "jailbreak" using grand central dispatch

    DOUIManager *uiManager = [DOUIManager sharedInstance];

    static BOOL didFinish = NO; //not thread safe lol
    

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [uiManager completeJailbreak];
        [uiManager sendLog:@"Rebooting Userspace" debug: NO];
        didFinish = YES;
        [self fadeToBlack: ^{

        }];
    });

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [NSThread sleepForTimeInterval:0.2];
        [uiManager sendLog:@"Launching kexploitd" debug: NO];
        [NSThread sleepForTimeInterval:0.5];
        [uiManager sendLog:@"Launching oobPCI" debug: NO];
        [NSThread sleepForTimeInterval:0.15];
        [uiManager sendLog:@"Gaining r/w" debug: NO];
        [NSThread sleepForTimeInterval:0.8];
        [uiManager sendLog:@"Patchfinding" debug: NO];
        NSArray *types = @[@"AMFI", @"PAC", @"KTRR", @"KPP", @"PPL", @"KPF", @"APRR", @"AMCC", @"PAN", @"PXN", @"ASLR", @"OPA"]; //Ever heard of the legendary opa bypass
        while (true)
        {
            [NSThread sleepForTimeInterval:0.6 * rand() / RAND_MAX];
            if (didFinish) break;
            NSString *type = types[arc4random_uniform((uint32_t)types.count)];
            [uiManager sendLog:[NSString stringWithFormat:@"Bypassing %@", type] debug: NO];
        }
    });
}

- (void)fadeToBlack:(void (^)(void))completion
{
    static bool didFade = false;
    if (didFade)
        return;
    didFade = true;
    UIView *mainView = self.parentViewController.view;
    float deviceCornerRadius = [[[UIScreen mainScreen] valueForKey:@"_displayCornerRadius"] floatValue];

    mainView.layer.cornerRadius = deviceCornerRadius;
    mainView.layer.cornerCurve = kCACornerCurveContinuous;
    mainView.layer.masksToBounds = YES;
    
    self.hideStatusBar = YES;

    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:2.0 options: UIViewAnimationOptionCurveEaseInOut animations:^{
        mainView.transform = CGAffineTransformMakeScale(0.9, 0.9);
        mainView.alpha = 0.0;
    } completion:^(BOOL success) {
        completion();
    }];
}

#pragma mark - Action Menu Delegate

- (BOOL)actionMenuShowsChevronForAction:(UIAction *)action
{
    if ([action.identifier isEqualToString:@"settings"] || [action.identifier isEqualToString:@"credits"]) return YES;
    return NO;
}

- (BOOL)actionMenuActionIsEnabled:(UIAction *)action
{
    if ([action.identifier isEqualToString:@"respring"] || [action.identifier isEqualToString:@"reboot-userspace"]) {
        return [[DOEnvironmentManager sharedManager] isJailbroken];
    }
    return YES;
}

#pragma mark - Status Bar

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

- (BOOL)prefersStatusBarHidden
{
    return self.hideStatusBar;
}

- (BOOL)prefersHomeIndicatorAutoHidden
{
    return self.hideHomeIndicator;
}

- (void)setHideStatusBar:(BOOL)hideStatusBar
{
    _hideStatusBar = hideStatusBar;
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)setHideHomeIndicator:(BOOL)hideHomeIndicator
{
    _hideHomeIndicator = hideHomeIndicator;
    [self setNeedsUpdateOfHomeIndicatorAutoHidden];
}

@end
