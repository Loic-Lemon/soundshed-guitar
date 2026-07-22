#include "PluginProcessorAdapter.h"
#include "PluginEditor.h"
#include <juce_audio_devices/juce_audio_devices.h>
#include <juce_audio_processors/juce_audio_processors.h>
#include <juce_audio_utils/juce_audio_utils.h>
#include <juce_audio_plugin_client/Standalone/juce_StandaloneFilterWindow.h>
#include <juce_gui_basics/juce_gui_basics.h>

#if JUCE_MAC
#import <Cocoa/Cocoa.h>

// Forward declaration
class MainWindow;

//==============================================================================
@interface SoundshedStatusBarController : NSObject <NSMenuDelegate>
{
    NSMenu *_contextMenu;
    id _rightClickMonitor;
}

@property (strong, nonatomic) NSStatusItem *statusItem;
@property (assign, nonatomic) NSWindow *mainWindow;
@property (assign, nonatomic) BOOL isToggling;

- (instancetype)init;
- (NSImage *)createStatusBarIcon;
- (void)attachToWindow:(NSWindow *)window;
- (void)detach;
- (void)showMainWindow;
- (void)hideMainWindow;
- (void)updateMenuItemTitle;
- (void)syncActivationPolicy;
- (void)handleQuit:(id)sender;
- (void)onWindowResignedKey:(NSNotification *)notification;

@end

//==============================================================================
@implementation SoundshedStatusBarController

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _isToggling = NO;
        _rightClickMonitor = nil;

        // Build the right-click context menu. We set _statusItem.menu = _contextMenu
        // only transiently, inside a right-click event monitor, so the system shows
        // it natively with proper styling. The menu is cleared again in menuDidClose:.

        _contextMenu = [[NSMenu alloc] init];
        [_contextMenu setDelegate:self];

        NSMenuItem *showHideItem = [[NSMenuItem alloc] initWithTitle:@"Hide Fork - Soundshed Guitar"
                                                              action:@selector(toggleWindowVisibility:)
                                                       keyEquivalent:@""];
        [showHideItem setTarget:self];
        [_contextMenu addItem:showHideItem];
        [showHideItem release];

        [_contextMenu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                                            action:@selector(handleQuit:)
                                                       keyEquivalent:@"q"];
        [quitItem setTarget:self];
        [_contextMenu addItem:quitItem];
        [quitItem release];

        // Create the status item. Left-click fires toggleWindowVisibility: directly.
        // Right-click is detected via a local event monitor that assigns _statusItem.menu
        // just-in-time, then the system displays it natively.
        _statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength] retain];
        _statusItem.button.image = [self createStatusBarIcon];
        [_statusItem.button sendActionOn:NSEventMaskLeftMouseDown];
        _statusItem.button.target = self;
        _statusItem.button.action = @selector(toggleWindowVisibility:);
        _statusItem.button.toolTip = @"Fork - Soundshed Guitar";
        [_statusItem setVisible:YES];

        // Local event monitor: on any right-mouse-down in our app, if the event
        // targets the status item button, set _statusItem.menu just-in-time so
        // the system renders it natively on right-click.
        // In MRC the block does not retain self, so capturing self directly is
        // safe — the monitor is always removed in detach (called from dealloc).
        _rightClickMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskRightMouseDown
            handler:^NSEvent *(NSEvent *event) {
                // If the right-click is not inside our main content window, it's
                // on the status item — set the menu just-in-time so the system
                // displays it natively. event.window is often nil for status bar
                // events, so we compare != _mainWindow instead of == button.window.
                if (event.window != self->_mainWindow)
                    self->_statusItem.menu = self->_contextMenu;
                return event;
            }];
    }
    return self;
}

// Draw a simple filled circle as the status bar icon.
// Returns a template image that renders correctly in both light and dark menu bars.
- (NSImage *)createStatusBarIcon
{
    const CGFloat size = 22.0;
    NSImage *icon = [[[NSImage alloc] initWithSize:NSMakeSize(size, size)] autorelease];
    [icon lockFocus];

    // Filled circle with 2pt padding
    [[NSColor blackColor] setFill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(3, 3, 16, 16)] fill];

    [icon unlockFocus];
    [icon setTemplate:YES];
    return icon;
}

- (void)attachToWindow:(NSWindow *)window
{
    _mainWindow = window;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onWindowResignedKey:)
                                                 name:NSWindowDidResignKeyNotification
                                               object:_mainWindow];
    [self showMainWindow];
}

- (void)detach
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    if (_rightClickMonitor)
    {
        [NSEvent removeMonitor:_rightClickMonitor];
        _rightClickMonitor = nil;
    }

    if (_statusItem)
    {
        _statusItem.menu = nil;
        [[NSStatusBar systemStatusBar] removeStatusItem:_statusItem];
        [_statusItem release];
        _statusItem = nil;
    }
    _mainWindow = nil;
}

- (void)dealloc
{
    [self detach];
    [_contextMenu release];
    [super dealloc];
}

- (IBAction)toggleWindowVisibility:(id)sender
{
    (void)sender;
    if (!_mainWindow)
        return;

    _isToggling = YES;
    if ([_mainWindow isVisible])
        [self hideMainWindow];
    else
        [self showMainWindow];
    _isToggling = NO;
}

//==============================================================================
#pragma mark - NSMenuDelegate

- (void)menuWillOpen:(NSMenu *)menu
{
    (void)menu;
    // Always clear the menu from the status item before the menu opens.
    // This prevents a stale _statusItem.menu from blocking left-click if
    // menuDidClose wasn't called for some reason (e.g. the menu failed to
    // display after the monitor set it).
    if (_statusItem)
        _statusItem.menu = nil;
    [self updateMenuItemTitle];
}

- (void)menuDidClose:(NSMenu *)menu
{
    if (_statusItem && _statusItem.menu == menu)
        _statusItem.menu = nil;
}

//==============================================================================
#pragma mark - Window management

- (void)showMainWindow
{
    if (!_mainWindow)
        return;

    [self syncActivationPolicy];
    [_mainWindow setLevel:NSFloatingWindowLevel];
    [NSApp activateIgnoringOtherApps:YES];
    [_mainWindow makeKeyAndOrderFront:nil];
    [self updateMenuItemTitle];
}

- (void)hideMainWindow
{
    if (!_mainWindow)
        return;

    [_mainWindow orderOut:nil];
    [self syncActivationPolicy];
    [self updateMenuItemTitle];
}

- (void)updateMenuItemTitle
{
    NSMenuItem *item = [[_contextMenu itemArray] firstObject];
    if (item)
    {
        if (_mainWindow && [_mainWindow isVisible])
            [item setTitle:@"Hide Fork - Soundshed Guitar"];
        else
            [item setTitle:@"Show Fork - Soundshed Guitar"];
    }
}

- (void)syncActivationPolicy
{
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
}

- (void)handleQuit:(id)sender
{
    // Save state before quitting
    if (_mainWindow && [_mainWindow isVisible])
        [_mainWindow performClose:nil];

    // Trigger the standard JUCE quit flow
    juce::JUCEApplication::getInstance()->systemRequestedQuit();
}

- (void)onWindowResignedKey:(NSNotification *)notification
{
    if (_isToggling || !_mainWindow)
        return;

    // Delay the check to allow in-app windows (e.g. file dialogs) to become key.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   ^{
        if (self->_isToggling || !self->_mainWindow)
            return;

        // If no app window is key, the user clicked outside the app.
        if ([NSApp keyWindow] == nil && [self->_mainWindow isVisible])
            [self hideMainWindow];
    });
}

@end

#endif // JUCE_MAC

//==============================================================================
namespace
{
    juce::String extractToneSharingDeepLinkQuery (juce::String commandLine)
    {
        auto normalized = juce::URL::removeEscapeChars (commandLine.unquoted().trim());

        auto extractValue = [&normalized] (const juce::String& key) -> juce::String
        {
            const auto marker = key + "=";
            const auto index = normalized.indexOfIgnoreCase (marker);
            if (index < 0)
                return {};

            auto value = normalized.substring (index + marker.length());
            const auto ampPos = value.indexOfChar ('&');
            if (ampPos >= 0)
                value = value.substring (0, ampPos);
            const auto spacePos = value.indexOfChar (' ');
            if (spacePos >= 0)
                value = value.substring (0, spacePos);
            const auto quotePos = value.indexOfChar ('\"');
            if (quotePos >= 0)
                value = value.substring (0, quotePos);
            const auto hashPos = value.indexOfChar ('#');
            if (hashPos >= 0)
                value = value.substring (0, hashPos);

            return value.trim();
        };

        const auto itemId = extractValue ("itemId");
        const auto packId = extractValue ("packId");

        juce::String sanitized;
        if (itemId.isNotEmpty())
            sanitized << "itemId=" << itemId;
        if (packId.isNotEmpty())
        {
            if (sanitized.isNotEmpty())
                sanitized << "&";
            sanitized << "packId=" << packId;
        }

        return sanitized;
    }
}

//==============================================================================
class MainWindow : public juce::DocumentWindow
{
public:
    explicit MainWindow (const juce::String& appName,
        std::unique_ptr<juce::StandalonePluginHolder> pluginHolderIn)
        : DocumentWindow (appName,
              juce::Desktop::getInstance().getDefaultLookAndFeel().findColour (juce::ResizableWindow::backgroundColourId),
              juce::DocumentWindow::allButtons),
          mPluginHolder (std::move (pluginHolderIn))
    {
        setUsingNativeTitleBar (false);
        setTitleBarHeight (0);
        setResizable (true, true);
        setResizeLimits (640, 400, 8192, 8192);

        // Pass the audio device manager to the plugin processor for device enumeration
        PluginProcessorAdapter::setStandaloneDeviceManager (&mPluginHolder->deviceManager);

        // Read window mode setting — determines Dock vs Menu bar behavior.
        if (auto* adapter = dynamic_cast<PluginProcessorAdapter*> (
                mPluginHolder != nullptr ? mPluginHolder->processor.get() : nullptr))
        {
            const auto& s = adapter->getController().GetAppSettings();
            const auto it = s.find ("appearance.windowMode");
            mMenuBarMode = it != s.end() && it->is_string() && it->get<std::string>() == "menuBar";
        }

        if (auto* processor = mPluginHolder != nullptr ? mPluginHolder->processor.get() : nullptr)
        {
            auto* editor = processor->hasEditor()
                               ? processor->createEditorIfNeeded()
                               : static_cast<juce::AudioProcessorEditor*> (new juce::GenericAudioProcessorEditor (*processor));

            if (editor != nullptr)
            {
                setContentOwned (editor, true);
                setResizable (editor->isResizable(), true);
            }
        }

        const auto state = loadWindowState();
        centreWithSize (state.width, state.height);

        if (state.maximized)
            setFullScreen (true);

        mPluginHolder->startPlaying();
        setVisible (true);

        if (mMenuBarMode)
            setAlwaysOnTop (true);

#if JUCE_MAC
        if (auto* peer = getPeer())
        {
            if (auto handle = peer->getNativeHandle())
            {
                NSView* view = (__bridge NSView*)handle;
                NSWindow* win = [view window];
                [win setOpaque:NO];
                [win setBackgroundColor:[NSColor clearColor]];
                [win.contentView setWantsLayer:YES];
                win.contentView.layer.cornerRadius = 12.0;
                win.contentView.layer.masksToBounds = YES;

                if (mMenuBarMode)
                {
                    [win setLevel:NSFloatingWindowLevel];

                    // In menu bar mode, the UI windowClose hides instead of quitting
                    const auto a = dynamic_cast<PluginProcessorAdapter*> (mPluginHolder->processor.get());
                    if (a != nullptr)
                    {
                        PluginProcessorAdapter::setOnStandaloneHideWindowRequested ([this]() {
                            juce::MessageManager::callAsync ([this]() {
                                setVisible (false);
                            });
                        });
                    }
                }
            }
        }
#endif
    }

    ~MainWindow() override
    {
        saveWindowState();

        if (auto* editor = dynamic_cast<juce::AudioProcessorEditor*> (getContentComponent()))
            if (auto* processor = mPluginHolder != nullptr ? mPluginHolder->processor.get() : nullptr)
                processor->editorBeingDeleted (editor);

        clearContentComponent();

        if (mPluginHolder != nullptr)
            mPluginHolder->stopPlaying();
    }

    void resized() override
    {
        juce::DocumentWindow::resized();

        if (!isFullScreen())
            mLastNonMaximizedBounds = getBounds();
    }

    void closeButtonPressed() override
    {
        saveWindowState();

        if (mPluginHolder != nullptr)
            mPluginHolder->savePluginState();

        if (mMenuBarMode)
            setVisible (false);
        else
            juce::JUCEApplication::getInstance()->systemRequestedQuit();
    }

    juce::StandalonePluginHolder* getPluginHolder() const noexcept
    {
        return mPluginHolder.get();
    }

#if JUCE_MAC
    NSWindow* getNSWindow() const
    {
        if (auto* peer = getPeer())
            if (auto handle = peer->getNativeHandle())
                return [(__bridge NSView*)handle window];
        return nil;
    }
#endif

    bool isWindowVisible() const { return isVisible(); }

    bool usesMenuBarMode() const noexcept { return mMenuBarMode; }

private:
    struct WindowState
    {
        int width = 1200;
        int height = 900;
        bool maximized = false;
    };

    juce::File getWindowStateFile() const
    {
        auto* adapter = dynamic_cast<PluginProcessorAdapter*> (
            mPluginHolder != nullptr ? mPluginHolder->processor.get() : nullptr);
        if (adapter == nullptr)
            return {};

        const auto path = adapter->GetUserDataPath() / "data" / "v1" / "settings" / "ui" / "window-state.json";
        return juce::File (path.string());
    }

    WindowState loadWindowState() const
    {
        WindowState state;

        const auto file = getWindowStateFile();
        if (file.existsAsFile())
        {
            const auto parsed = juce::JSON::parse (file.loadFileAsString());
            if (auto* obj = parsed.getDynamicObject(); obj != nullptr)
            {
                const auto widthId = juce::Identifier { "width" };
                const auto heightId = juce::Identifier { "height" };
                const auto maximizedId = juce::Identifier { "maximized" };

                if (obj->hasProperty (widthId))
                    state.width = static_cast<int> (obj->getProperty (widthId));
                if (obj->hasProperty (heightId))
                    state.height = static_cast<int> (obj->getProperty (heightId));
                if (obj->hasProperty (maximizedId))
                    state.maximized = static_cast<bool> (obj->getProperty (maximizedId));
            }
        }

        // Clamp to the primary display's usable area.
        if (auto* primary = juce::Desktop::getInstance().getDisplays().getPrimaryDisplay())
        {
            const auto userArea = primary->userArea;
            state.width = juce::jmin (state.width, userArea.getWidth());
            state.height = juce::jmin (state.height, userArea.getHeight());
        }

        state.width = juce::jlimit (1024, 8192, state.width);
        state.height = juce::jlimit (768, 8192, state.height);

        return state;
    }

    void saveWindowState() const
    {
        const auto file = getWindowStateFile();
        if (file == juce::File {})
            return;

        file.getParentDirectory().createDirectory();

        juce::DynamicObject::Ptr state (new juce::DynamicObject());
        state->setProperty ("width", mLastNonMaximizedBounds.getWidth());
        state->setProperty ("height", mLastNonMaximizedBounds.getHeight());
        state->setProperty ("maximized", isFullScreen());
        file.replaceWithText (juce::JSON::toString (juce::var (state)));
    }

    std::unique_ptr<juce::StandalonePluginHolder> mPluginHolder;
    bool mMenuBarMode = false;

    juce::Rectangle<int> mLastNonMaximizedBounds { 0, 0, 1200, 900 };
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (MainWindow)
};

//==============================================================================
class SoundshedGuitarApplication : public juce::JUCEApplication
{
public:
    SoundshedGuitarApplication()
    {
        juce::PropertiesFile::Options options;
        options.applicationName = PRODUCT_NAME_WITHOUT_VERSION;
        options.filenameSuffix = ".settings";
        options.osxLibrarySubFolder = "Application Support";
#if JUCE_LINUX || JUCE_BSD
        options.folderName = "~/.config";
#else
        options.folderName = {};
#endif
        mAppProperties.setStorageParameters (options);
    }

    const juce::String getApplicationName() override { return PRODUCT_NAME_WITHOUT_VERSION; }
    const juce::String getApplicationVersion() override { return JucePlugin_VersionString; }
    bool moreThanOneInstanceAllowed() override { return false; }

    void initialise (const juce::String&) override
    {
        if (juce::Desktop::getInstance().getDisplays().displays.isEmpty())
        {
            jassertfalse;
            return;
        }

        mMainWindow = std::make_unique<MainWindow> (getApplicationName(), createPluginHolder());

#if JUCE_MAC
        // Create and attach the menu bar status item (only in menu bar mode)
        if (auto* mainWin = dynamic_cast<MainWindow*> (mMainWindow.get()))
        {
            if (mainWin->usesMenuBarMode())
            {
                if (NSWindow* nativeWin = mainWin->getNSWindow())
                {
                    mStatusBarController = [[SoundshedStatusBarController alloc] init];
                    [mStatusBarController attachToWindow:nativeWin];
                }
            }
        }
#endif
    }

    void shutdown() override
    {
#if JUCE_MAC
        if (mStatusBarController != nil)
        {
            [mStatusBarController detach];
            [mStatusBarController release];
            mStatusBarController = nil;
        }
#endif
        mMainWindow = nullptr;
        mAppProperties.saveIfNeeded();
    }

    void systemRequestedQuit() override
    {
        if (mMainWindow != nullptr)
            if (auto* holder = mMainWindow->getPluginHolder())
                holder->savePluginState();

        if (juce::ModalComponentManager::getInstance()->cancelAllModalComponents())
        {
            juce::Timer::callAfterDelay (100, []() {
                if (auto* app = juce::JUCEApplicationBase::getInstance())
                    app->systemRequestedQuit();
            });

            return;
        }

        quit();
    }

    void anotherInstanceStarted (const juce::String& commandLine) override
    {
        // In menu bar mode: show the window if it was hidden (e.g. the user had
        // closed it but the app was still running in the menu bar). A new instance
        // implies user intent to interact with the app (e.g. a soundshed:// deep link).
        if (mMainWindow != nullptr && mMainWindow->usesMenuBarMode() && !mMainWindow->isWindowVisible())
            mMainWindow->setVisible (true);

        // Extract deep link from incoming command line and route to existing instance
        const auto deepLink = extractToneSharingDeepLinkQuery (commandLine);
        if (deepLink.isNotEmpty() && mMainWindow != nullptr)
        {
            if (auto* editor = dynamic_cast<PluginEditor*> (mMainWindow->getContentComponent()))
            {
                juce::MessageManager::callAsync ([editor, deepLink]() {
                    editor->handleDeepLinkFromAnotherInstance (deepLink);
                });
            }
        }
    }

private:
    std::unique_ptr<juce::StandalonePluginHolder> createPluginHolder()
    {
        constexpr auto autoOpenMidiDevices =
#if (JUCE_ANDROID || JUCE_IOS) && !JUCE_DONT_AUTO_OPEN_MIDI_DEVICES_ON_MOBILE
            true;
#else
            false;
#endif

#ifdef JucePlugin_PreferredChannelConfigurations
        constexpr juce::StandalonePluginHolder::PluginInOuts channels[] { JucePlugin_PreferredChannelConfigurations };
        const juce::Array<juce::StandalonePluginHolder::PluginInOuts> channelConfig (channels, juce::numElementsInArray (channels));
#else
        const juce::Array<juce::StandalonePluginHolder::PluginInOuts> channelConfig;
#endif

        return std::make_unique<juce::StandalonePluginHolder> (mAppProperties.getUserSettings(),
            false,
            juce::String {},
            nullptr,
            channelConfig,
            autoOpenMidiDevices);
    }

    juce::ApplicationProperties mAppProperties;
    std::unique_ptr<MainWindow> mMainWindow;

#if JUCE_MAC
    SoundshedStatusBarController* mStatusBarController = nil;
#endif
};

namespace juce
{
    void JUCE_CALLTYPE juce_showStandaloneAudioSettingsDialog()
    {
        if (auto* holder = StandalonePluginHolder::getInstance())
            holder->showAudioSettingsDialog();
    }
}

//==============================================================================
START_JUCE_APPLICATION (SoundshedGuitarApplication)
