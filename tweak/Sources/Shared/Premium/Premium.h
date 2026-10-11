// Premium: makes a free Spotify account behave as premium on this device, keeping the login. The
// account attributes it forces (type=premium, ads off, on-demand, offline, unrestricted, ...) and the
// free-tier capping flags it strips are taken from EeveeSpotifyReborn
// (github.com/whoeevee/EeveeSpotifyReborn, Sources/EeveeSpotify/Premium): the same table, ported to
// spoti.pw's two surfaces. Eevee rewrites Spotify's /v1/bootstrap protobuf as it arrives; here the
// account attributes are answered at the product-state object the client reads, and the capping flags
// go through the mod's own flag forcer (Core/SGFlagForce.h, the same one the Search switches use).
// Nothing is bought and nothing leaves the device; server-side limits Spotify keeps off the client
// are not touched.
//
// A toggle on Mod Settings turns the whole thing on or off; like every switch it is read at launch,
// so a change takes a restart. The product-state class is Spotify's, obfuscated and version specific,
// so Premium.x finds it at runtime rather than naming it, and logs when it cannot (prove the class
// with a header dump and add its selector, as AGENTS.md asks of any hook).
#import <UIKit/UIKit.h>
#import "Settings/SGModPage.h"

// Unset reads on, so a fresh build is premium until the switch is turned off.
#define SGKeyPremium @"spotifyglass.premium"

BOOL SGPremiumEnabled(void);   // the switch as it was at launch

SGModRow *SGPremiumRow(void);
UIViewController *SGPremiumSettingsPage(void);
