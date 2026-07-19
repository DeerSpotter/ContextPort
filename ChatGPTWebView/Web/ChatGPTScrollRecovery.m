#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

static const void *CPChatGPTScrollScriptInstalledKey = &CPChatGPTScrollScriptInstalledKey;
static const void *CPChatGPTScrollRecoveryGenerationKey = &CPChatGPTScrollRecoveryGenerationKey;

static NSString * const CPProgressiveChatAccessEnabledKey = @"ProgressiveChatAccessEnabled";
static NSString * const CPProgressiveChatAccessBucketCountKey = @"ProgressiveChatAccessBucketCount";
static NSString * const CPProgressiveAccessSettingsDidChangeNotification = @"ContextPortProgressiveAccessSettingsDidChange";

static NSHashTable<WKWebView *> *CPProgressiveAccessWebViews;

@interface WKWebView (ContextPortChatGPTScrollRecovery)
- (void)cp_scrollRecovery_didMoveToWindow;
- (void)cp_scheduleChatGPTScrollRecovery;
@end

@implementation WKWebView (ContextPortChatGPTScrollRecovery)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CPProgressiveAccessWebViews = [NSHashTable weakObjectsHashTable];

        Method originalMove = class_getInstanceMethod(self, @selector(didMoveToWindow));
        Method replacementMove = class_getInstanceMethod(self, @selector(cp_scrollRecovery_didMoveToWindow));
        method_exchangeImplementations(originalMove, replacementMove);

        [[NSNotificationCenter defaultCenter]
            addObserverForName:CPProgressiveAccessSettingsDidChangeNotification
            object:nil
            queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *notification) {
                for (WKWebView *webView in CPProgressiveAccessWebViews.allObjects) {
                    [webView cp_scheduleChatGPTScrollRecovery];
                }
            }];
    });
}

- (void)cp_scrollRecovery_didMoveToWindow {
    [self cp_scrollRecovery_didMoveToWindow];
    [CPProgressiveAccessWebViews addObject:self];
    [self cp_installChatGPTScrollRecoveryScriptIfNeeded];
    [self cp_scheduleChatGPTScrollRecovery];
}

- (BOOL)cp_isChatGPTScrollRecoveryURL:(NSURL *)url {
    NSString *host = url.host.lowercaseString;
    if (host.length == 0) return NO;
    return [host isEqualToString:@"chatgpt.com"] || [host hasSuffix:@".chatgpt.com"];
}

- (BOOL)cp_progressiveChatAccessEnabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:CPProgressiveChatAccessEnabledKey] == nil) {
        return YES;
    }
    return [defaults boolForKey:CPProgressiveChatAccessEnabledKey];
}

- (NSInteger)cp_progressiveAccessBucketCount {
    NSInteger count = [[NSUserDefaults standardUserDefaults]
        integerForKey:CPProgressiveChatAccessBucketCountKey];
    if (count <= 0) count = 6;
    return MIN(MAX(count, 1), 12);
}

- (void)cp_prepareNativeScrollViewForChatGPT {
    UIScrollView *scrollView = self.scrollView;
    scrollView.scrollEnabled = YES;
    scrollView.userInteractionEnabled = YES;
    scrollView.directionalLockEnabled = YES;
    scrollView.panGestureRecognizer.enabled = YES;
    scrollView.delaysContentTouches = NO;

    // ChatGPT normally scrolls inside its own DOM container. Keep the outer
    // WKWebView stable while leaving vertical interaction enabled.
    scrollView.bounces = NO;
    scrollView.alwaysBounceVertical = NO;
    scrollView.alwaysBounceHorizontal = NO;
    scrollView.showsHorizontalScrollIndicator = NO;
}

- (void)cp_installChatGPTScrollRecoveryScriptIfNeeded {
    if ([objc_getAssociatedObject(self, CPChatGPTScrollScriptInstalledKey) boolValue]) return;

    WKUserScript *script = [[WKUserScript alloc]
        initWithSource:[self cp_chatGPTScrollRecoveryScript]
        injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
        forMainFrameOnly:YES];
    [self.configuration.userContentController addUserScript:script];
    objc_setAssociatedObject(self, CPChatGPTScrollScriptInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)cp_scheduleChatGPTScrollRecovery {
    NSNumber *generation = objc_getAssociatedObject(self, CPChatGPTScrollRecoveryGenerationKey);
    NSInteger nextGeneration = generation.integerValue + 1;
    objc_setAssociatedObject(
        self,
        CPChatGPTScrollRecoveryGenerationKey,
        @(nextGeneration),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    if (![self cp_progressiveChatAccessEnabled]) return;

    [self cp_prepareNativeScrollViewForChatGPT];

    NSArray<NSNumber *> *allDelays = @[
        @0.25, @0.75, @2.0, @5.0, @10.0, @16.0,
        @24.0, @32.0, @45.0, @60.0, @90.0, @120.0
    ];
    NSInteger bucketCount = [self cp_progressiveAccessBucketCount];
    NSArray<NSNumber *> *delays = [allDelays subarrayWithRange:NSMakeRange(0, bucketCount)];

    NSLog(
        @"[ContextPort] Progressive Chat Access scheduled with %ld access buckets.",
        (long)bucketCount
    );

    __weak WKWebView *weakWebView = self;
    for (NSNumber *delay in delays) {
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
            dispatch_get_main_queue(),
            ^{
                WKWebView *webView = weakWebView;
                if (!webView || ![webView cp_isChatGPTScrollRecoveryURL:webView.URL]) return;

                NSNumber *currentGeneration = objc_getAssociatedObject(
                    webView,
                    CPChatGPTScrollRecoveryGenerationKey
                );
                if (currentGeneration.integerValue != nextGeneration) return;
                if (![webView cp_progressiveChatAccessEnabled]) return;

                [webView cp_prepareNativeScrollViewForChatGPT];
                [webView evaluateJavaScript:[webView cp_chatGPTScrollRecoveryScript]
                          completionHandler:nil];
            }
        );
    }
}

- (NSString *)cp_chatGPTScrollRecoveryScript {
    return           @"(() => {"
           "  try {"
           "    if (!/(^|\\.)chatgpt\\.com$/.test(location.hostname)) return false;"
           "    const manager = window.__contextPortChatPerformance;"
           "    if (manager && manager.providerID === 'chatgpt' && typeof manager.destroy === 'function') manager.destroy();"
           "    document.getElementById('contextport-chat-performance-style')?.remove();"
           "    document.querySelectorAll('.contextport-performance-hidden').forEach(element => {"
           "      element.classList.remove('contextport-performance-hidden');"
           "      element.removeAttribute('aria-hidden');"
           "      element.removeAttribute('data-contextport-performance-message');"
           "    });"
           ""
           "    const stateKey = '__contextPortChatScrollRecoveryState';"
           "    const currentURL = location.href;"
           "    const previous = window[stateKey];"
           "    if (previous?.observer) {"
           "      try { previous.observer.disconnect(); } catch (_) {}"
           "      previous.observer = null;"
           "    }"
           "    if (previous?.timer) {"
           "      clearTimeout(previous.timer);"
           "      previous.timer = null;"
           "    }"
           "    if (previous && previous.url !== currentURL && typeof previous.resetForURL === 'function') {"
           "      previous.resetForURL(currentURL);"
           "    }"
           ""
           "    const state = window[stateKey] || {"
           "      url: currentURL,"
           "      followLatest: true,"
           "      scrollTarget: null,"
           "      scrollListener: null,"
           "      lastTop: 0,"
           "      programmaticUntil: 0,"
           "      followTimer: null,"
           "      destroy: null,"
           "      resetForURL: null"
           "    };"
           "    window[stateKey] = state;"
           ""
           "    const turnSelector = '[data-message-author-role], section[data-testid^=conversation-turn-], [data-testid*=conversation-turn]';"
           "    const candidateSelector = 'main, [role=main], [data-scroll-root], [class*=overflow-y-auto], [class*=overflow-y-scroll], [style*=overflow-y]';"
           "    const distanceFromBottom = element => Math.max(0, element.scrollHeight - element.clientHeight - element.scrollTop);"
           ""
           "    const detachTarget = () => {"
           "      if (state.scrollTarget && state.scrollListener) {"
           "        state.scrollTarget.removeEventListener('scroll', state.scrollListener);"
           "      }"
           "      state.scrollTarget = null;"
           "      state.scrollListener = null;"
           "      state.lastTop = 0;"
           "    };"
           ""
           "    state.resetForURL = url => {"
           "      state.url = url;"
           "      state.followLatest = true;"
           "      state.programmaticUntil = 0;"
           "      detachTarget();"
           "    };"
           ""
           "    const isVisible = element => {"
           "      const rect = element.getBoundingClientRect();"
           "      return rect.width > 0 && rect.height > 0 && rect.bottom > 0 && rect.top < window.innerHeight;"
           "    };"
           ""
           "    const isUsableTarget = element => {"
           "      if (!(element instanceof HTMLElement) || !element.isConnected || !isVisible(element)) return false;"
           "      return element.clientHeight >= 160 && element.scrollHeight - element.clientHeight >= 40;"
           "    };"
           ""
           "    const findBest = () => {"
           "      const items = ["
           "        document.scrollingElement,"
           "        document.documentElement,"
           "        document.body,"
           "        ...document.querySelectorAll(candidateSelector)"
           "      ];"
           "      let best = null;"
           "      let bestScore = -1;"
           "      for (const element of Array.from(new Set(items.filter(Boolean)))) {"
           "        if (!(element instanceof HTMLElement)) continue;"
           "        const range = Math.max(0, element.scrollHeight - element.clientHeight);"
           "        if (range < 40 || element.clientHeight < 160 || !isVisible(element)) continue;"
           "        const containsConversation = Boolean(element.querySelector(turnSelector));"
           "        const inMain = element.matches('main, [role=main]') || Boolean(element.closest('main, [role=main]'));"
           "        const score = range + element.clientHeight * 4"
           "          + (containsConversation ? 10000000 : 0)"
           "          + (inMain ? 1000000 : 0);"
           "        if (score > bestScore) {"
           "          best = element;"
           "          bestScore = score;"
           "        }"
           "      }"
           "      return best;"
           "    };"
           ""
           "    const configureTarget = element => {"
           "      element.style.setProperty('overflow-y', 'auto', 'important');"
           "      element.style.setProperty('overflow-x', 'hidden', 'important');"
           "      element.style.setProperty('-webkit-overflow-scrolling', 'touch', 'important');"
           "      element.style.setProperty('touch-action', 'pan-y', 'important');"
           "      element.style.setProperty('overscroll-behavior-y', 'contain', 'important');"
           "      element.style.setProperty('overscroll-behavior-x', 'none', 'important');"
           "      document.documentElement.style.setProperty('overflow-x', 'hidden', 'important');"
           "      document.documentElement.style.setProperty('overscroll-behavior-x', 'none', 'important');"
           "      document.body?.style.setProperty('overflow-x', 'hidden', 'important');"
           "      document.body?.style.setProperty('overscroll-behavior-x', 'none', 'important');"
           "    };"
           ""
           "    const attachTarget = element => {"
           "      if (state.scrollTarget === element && state.scrollListener) return;"
           "      detachTarget();"
           "      state.scrollTarget = element;"
           "      state.lastTop = element.scrollTop;"
           "      state.scrollListener = () => {"
           "        const top = element.scrollTop;"
           "        const distance = distanceFromBottom(element);"
           "        if (Date.now() < state.programmaticUntil) {"
           "          state.lastTop = top;"
           "          return;"
           "        }"
           "        if (distance <= 80) {"
           "          state.followLatest = true;"
           "        } else if (top < state.lastTop - 4) {"
           "          state.followLatest = false;"
           "        }"
           "        state.lastTop = top;"
           "      };"
           "      element.addEventListener('scroll', state.scrollListener, {passive: true});"
           "      configureTarget(element);"
           "    };"
           ""
           "    const acquireTarget = forceFollow => {"
           "      if (forceFollow) state.followLatest = true;"
           "      if (isUsableTarget(state.scrollTarget)) return state.scrollTarget;"
           "      detachTarget();"
           "      const target = findBest();"
           "      if (!target) return null;"
           "      attachTarget(target);"
           "      return target;"
           "    };"
           ""
           "    const pinToBottom = element => {"
           "      if (distanceFromBottom(element) <= 2) {"
           "        state.lastTop = element.scrollTop;"
           "        return;"
           "      }"
           "      state.programmaticUntil = Date.now() + 250;"
           "      element.scrollLeft = 0;"
           "      element.scrollTop = element.scrollHeight;"
           "      state.lastTop = element.scrollTop;"
           "    };"
           ""
           "    const tick = () => {"
           "      if (location.href !== state.url) state.resetForURL(location.href);"
           "      if (!state.followLatest) return;"
           "      const target = acquireTarget(false);"
           "      if (target) pinToBottom(target);"
           "    };"
           ""
           "    state.destroy = () => {"
           "      if (state.followTimer) clearInterval(state.followTimer);"
           "      state.followTimer = null;"
           "      detachTarget();"
           "    };"
           ""
           "    window.__contextPortScrollToBottom = () => {"
           "      const target = acquireTarget(true);"
           "      if (!target) return false;"
           "      pinToBottom(target);"
           "      return true;"
           "    };"
           "    window.__contextPortIsFollowingLatest = () => Boolean(state.followLatest);"
           ""
           "    tick();"
           "    if (!state.followTimer) state.followTimer = setInterval(tick, 500);"
           "    return true;"
           "  } catch (_) {"
           "    return false;"
           "  }"
           "})()";
}

@end
