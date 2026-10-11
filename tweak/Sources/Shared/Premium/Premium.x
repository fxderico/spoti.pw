// Two surfaces, both from EeveeSpotifyReborn's Premium patch:
//
//   1. Account attributes. Spotify keeps the account's entitlements in a product-state object and
//      asks it, by string key, "is this premium", "are ads on", "is on-demand allowed". We answer
//      those keys with Eevee's modifyAttributes() table when the switch is on. The object's class is
//      obfuscated and moves between versions, so instead of naming it we walk the runtime at launch
//      for whatever class answers the product-state accessors and swizzle those, keeping each
//      original IMP in the block that replaces it. A key not in the table falls straight through.
//
//   2. Capping flags. Eevee removes a set of free-tier remote-config properties (common capping,
//      pick-and-shuffle caps, the playback timeout, the mft-plus queue limits). The mod already
//      forces remote-config flags through Core/SGFlagForce.h, so we register a forcer that matches
//      those properties by name (the part after the last dot, so the component prefix does not
//      matter) and hands back the value that disables each.
#import "Core/SGCore.h"
#import "Premium.h"
#import <objc/runtime.h>

BOOL SGPremiumEnabled(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ on = SGEnabled(SGKeyPremium); });   // read once, at launch, like every switch
    return on;
}

#pragma mark - account attributes (Eevee modifyAttributes)

// Canonical string per key; the bool accessor reads a bool off it (anything but "" and "0" is true),
// the string accessor hands it back as is. Values are Eevee's, dropped in verbatim; the two dates are
// a year out, filled at launch. type/ads/on-demand are what the premium gates actually read.
static NSDictionary<NSString *, NSString *> *overrides(void) {
    static NSDictionary *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSDateFormatter *iso = [NSDateFormatter new];
        iso.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        iso.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        iso.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
        NSString *oneYear = [iso stringFromDate:[NSCalendar.currentCalendar dateByAddingUnit:NSCalendarUnitYear
                                                                                       value:1 toDate:[NSDate date] options:0]];
        table = @{
            @"ads":                          @"0",
            @"can_use_superbird":            @"1",
            @"catalogue":                    @"premium",
            @"financial-product":            @"pr:premium,tc:0",
            @"is-eligible-premium-unboxing": @"1",
            @"name":                         @"Spotify Premium",
            @"nft-disabled":                 @"1",
            @"offline":                      @"1",
            @"on-demand":                    @"1",
            @"payments-initial-campaign":    @"default",
            @"player-license":               @"premium",
            @"player-license-v2":            @"premium",
            @"product-expiry":               oneYear,
            @"shuffle-eligible":             @"1",
            @"social-session":               @"1",
            @"social-session-free-tier":     @"0",
            @"streaming-rules":              @"",
            @"subscription-enddate":         oneYear,
            @"type":                         @"premium",
            @"unrestricted":                 @"1",
        };
    });
    return table;
}

static NSString *overrideFor(NSString *key) {
    if (!key || !SGPremiumEnabled()) return nil;
    return overrides()[key];
}

static BOOL boolFromValue(NSString *value) {
    return value.length && ![value isEqualToString:@"0"] && ![value isEqualToString:@"false"];
}

static BOOL looksLikeProductState(Class cls, SEL probes[], int probeCount) {
    const char *name = class_getName(cls);
    if (!name || !strcasestr(name, "productstate")) return NO;
    for (int i = 0; i < probeCount; i++)
        if (class_getInstanceMethod(cls, probes[i])) return YES;
    return NO;
}

static void hookKeyAccessor(Class cls, SEL sel, BOOL returnsBool) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP orig = method_getImplementation(m);
    IMP replacement;
    if (returnsBool) {
        BOOL (*origFn)(id, SEL, id) = (BOOL (*)(id, SEL, id))orig;
        replacement = imp_implementationWithBlock(^BOOL(id self, NSString *key) {
            NSString *forced = overrideFor(key);
            return forced ? boolFromValue(forced) : origFn(self, sel, key);
        });
    } else {
        NSString *(*origFn)(id, SEL, id) = (NSString *(*)(id, SEL, id))orig;
        replacement = imp_implementationWithBlock(^NSString *(id self, NSString *key) {
            NSString *forced = overrideFor(key);
            return forced ?: origFn(self, sel, key);
        });
    }
    method_setImplementation(m, replacement);
}

// The whole-bag accessor: merge the overrides onto whatever Spotify returns.
static void hookMapAccessor(Class cls, SEL sel) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    IMP orig = method_getImplementation(m);
    id (*origFn)(id, SEL) = (id (*)(id, SEL))orig;
    IMP replacement = imp_implementationWithBlock(^id(id self) {
        id value = origFn(self, sel);
        if (!SGPremiumEnabled() || ![value isKindOfClass:NSDictionary.class]) return value;
        NSMutableDictionary *merged = [value mutableCopy];
        [merged addEntriesFromDictionary:overrides()];
        return merged;
    });
    method_setImplementation(m, replacement);
}

static void hookProductState(void) {
    SEL stringKeys[] = { @selector(stringForKey:), @selector(productStateWithKey:),
                         @selector(productStateStringForKey:), @selector(valueForProductStateKey:) };
    SEL boolKeys[]   = { @selector(boolForKey:), @selector(isEnabledForKey:), @selector(boolValueForKey:) };
    SEL mapSels[]    = { @selector(productStateMap), @selector(productStateDictionary),
                         @selector(allProductStates), @selector(values) };

    SEL probes[12]; int pc = 0;
    for (unsigned i = 0; i < sizeof(stringKeys)/sizeof(SEL); i++) probes[pc++] = stringKeys[i];
    for (unsigned i = 0; i < sizeof(boolKeys)/sizeof(SEL); i++)   probes[pc++] = boolKeys[i];
    for (unsigned i = 0; i < sizeof(mapSels)/sizeof(SEL); i++)    probes[pc++] = mapSels[i];

    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return;
    Class *classes = (Class *)malloc(sizeof(Class) * count);
    count = objc_getClassList(classes, count);

    int hooked = 0;
    for (int i = 0; i < count; i++) {
        Class cls = classes[i];
        if (!looksLikeProductState(cls, probes, pc)) continue;
        for (unsigned j = 0; j < sizeof(stringKeys)/sizeof(SEL); j++) hookKeyAccessor(cls, stringKeys[j], NO);
        for (unsigned j = 0; j < sizeof(boolKeys)/sizeof(SEL); j++)   hookKeyAccessor(cls, boolKeys[j], YES);
        for (unsigned j = 0; j < sizeof(mapSels)/sizeof(SEL); j++)    hookMapAccessor(cls, mapSels[j]);
        SGLog(@"premium: forced product state on %s", class_getName(cls));
        hooked++;
    }
    free(classes);
    if (!hooked) SGLog(@"premium: no product-state class found; prove the class with a header dump and add its selector");
}

#pragma mark - capping flags (Eevee propertyReplacements), through the mod's flag forcer

// The property after the last dot; Eevee matches by name, so the component prefix is dropped.
static NSString *propertyName(NSString *key) {
    NSRange dot = [key rangeOfString:@"." options:NSBackwardsSearch];
    return dot.location == NSNotFound ? key : [key substringFromIndex:dot.location + 1];
}

static id cappingForce(NSString *key) {
    static NSSet *disable;      // enabling flags to turn off, and the caps
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        disable = [NSSet setWithArray:@[
            @"enable_common_capping", @"enable_pns_common_capping",
            @"enable_pick_and_shuffle_common_capping", @"enable_pick_and_shuffle_dynamic_cap",
            @"enable_free_on_demand_experiment", @"enable_free_on_demand_context_menu_experiment",
            @"enable_mft_plus_queue", @"enable_mft_plus_extended_queue",
            @"is_remove_from_queue_enabled_for_mft_plus", @"is_reordering_for_mft_plus_allowed",
            @"should_nova_scroll_use_scrollsita",
            @"enable_playback_timeout_service", @"enable_playback_timeout_error_ui",
        ]];
    });
    NSString *name = propertyName(key);
    if ([name isEqualToString:@"playback_timeout_action"]) return @"Nothing";   // enum
    if ([name isEqualToString:@"pick_and_shuffle_timecap"]) return @(0);        // int cap
    if ([disable containsObject:name]) return @NO;                             // bool
    return nil;
}

%ctor {
    if (!SGPremiumEnabled()) return;   // nothing hooked when off; a restart turns it on or off
    hookProductState();
    // Beat an override from the All flags page, so a flag someone flipped there does not re-cap.
    SGRegisterFlagForcer(YES, ^id(NSString *key) { return cappingForce(key); }, nil);
}
