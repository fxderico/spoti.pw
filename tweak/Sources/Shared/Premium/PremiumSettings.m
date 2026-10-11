#import "Premium.h"

// The enable/disable switch and the page it sits on. On by default (the key reads on until switched
// off). Product state and the capping forcer are set at launch, so the footer asks for the restart.
SGModRow *SGPremiumRow(void) {
    return SGWithSymbol(SGSwitchRow(@"Spotify Premium",
                                    @"No ads, unlimited skips, on-demand play and downloads on this account",
                                    SGKeyPremium),
                        @"crown");
}

UIViewController *SGPremiumSettingsPage(void) {
    NSString *intro = @"Makes Spotify treat this account as premium on this device while you stay "
                      @"logged in as yourself: it answers the premium questions the app asks of your "
                      @"account and drops the free-tier limits. The method and values are "
                      @"EeveeSpotifyReborn's. Nothing is purchased and nothing leaves the phone.";
    return [[SGModPage alloc] initWithTitle:@"Premium" intro:intro sections:@[
        SGSection(nil, @[SGPremiumRow()]),
    ] footer:SGRestartNote];
}
