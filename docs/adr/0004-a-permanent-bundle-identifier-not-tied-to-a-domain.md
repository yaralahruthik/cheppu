---
status: accepted
---

# A permanent bundle identifier, not tied to a domain

The obvious path, once `cheppu.app` is bought, is to name the app `app.cheppu.Cheppu` and let the identifier match the domain the way most Mac apps do. We chose instead to ship as `com.iamyhr.cheppu`, set in `App/Info.plist`, and to never change it. `cheppu.app` will host the marketing site and nothing else.

Apple requires a reverse-DNS *style* identifier, not proof that you own the domain, so `iamyhr.com` backs the identifier perfectly well. The deeper reason is that on macOS the bundle identifier is not a name. It is the key the system files a user's trust under: TCC keys the Microphone and Accessibility grants to the identifier and the code signature together. Changing it after release revokes both for every existing user, silently, and sends them back through Onboarding — which for a dictation app is very nearly the whole product. An identifier is worth choosing once, for reasons that cannot expire.

## Considered options

- **`app.cheppu.Cheppu`, matching a domain we intend to own**: reads better and buys nothing. It would require owning the domain before the first signed release, and it permanently couples the app's identity to a registration that has to be renewed.
- **Shipping as `com.iamyhr.cheppu` now and renaming once `cheppu.app` is bought**: rejected because the cost is paid by users rather than by us, and it grows with every install. There is no version of this migration that does not ask people to re-grant permissions by hand.

## Consequences

- `CFBundleIdentifier` is fixed. Signing, notarization, the Developer portal App ID, the Homebrew cask's uninstall stanza, and the `UserDefaults` suite that holds Settings and History all key off it, and none of them need revisiting when the domain is bought.
- The Sparkle appcast URL is baked into every shipped binary and polled forever, so it points at a host we control permanently rather than at `cheppu.app`. A marketing site that changes host or gets rebuilt must never be able to strand a user on an old version.
- `cheppu.app` is a marketing concern only. Nothing in the app, the bundle, or the update path may depend on it, so the domain can be bought, moved, or dropped without cutting a release.
- The reverse is also true: letting `iamyhr.com` go would not affect the app. The identifier is a string, not a lookup.
