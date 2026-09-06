# App Store Featuring Nomination — Goals 1.0.2

Prep sheet for **App Store Connect → Features → Featuring Nominations**
(<https://appstoreconnect.apple.com/featuring>). Editors read English, so paste-ready copy is
in English. Nominating is free, non-binding, and repeatable per release.

**Angle:** current release, on its merits — a personal goal tracker built entirely with Apple
frameworks, fully offline, privacy-first.

---

## 0. Name your Nomination  *(internal label, not shown to editors/users)*

```
Goals 1.0.2 — built with Apple frameworks, privacy-first (Sep 2026)
```

## 1. Nomination type

**New app** (first release, 1.0.2). Secondary angles if the form allows more than one:
*design & craft*, *built with Apple technologies*, *privacy*.

## 2. Availability / launch date

The app is already live (or about to be) — use the **1.0.2 release date**. No need to wait for
a future build; you can nominate an app that's already on the Store.

## 3. Verify before you submit (repo vs. reality)

| Claim | Repo says | Use in nomination |
|---|---|---|
| Min iOS | `IPHONEOS_DEPLOYMENT_TARGET = 17.0` (both configs) | **iOS 17** — README's "iOS 26.5" is stale, don't repeat it |
| Version | `MARKETING_VERSION = 1.0.2`, build 7 | first public release → nominate as a **new app** |
| Widgets | 4 kinds in `GoalsWidgetBundle` (Goals, SingleGoal, Activity, ProgressChart) × 3 sizes | "multiple widget types across all three sizes" |
| Languages | `knownRegions` = en, cs, de, es, fr, pt-BR | **6 languages** |
| Live Activities / Dynamic Island | none (the "ActivityWidget" is a Home Screen check-in grid) | do **not** claim |
| iCloud / CloudKit / HealthKit | not used, by design | do **not** claim; the offline story is the angle instead |
| Third-party SDKs | none (Google sign-in is hand-rolled OAuth + PKCE) | "zero third-party dependencies" — strong editorial hook |

Also make sure the **App Store product page** (description, keywords, screenshots, preview) is
finished and consistent with the copy below — editors look at the live page.

## 4. What's noteworthy  *(main free-text box, keep ~500 chars)*

> Goals is a personal goal tracker built entirely with Apple frameworks — SwiftUI, SwiftData,
> WidgetKit, App Intents, Swift Charts, StoreKit 2 — and zero third-party dependencies.
> Everything lives on device: no account required, no server, no data collection. Track goals
> numerically or by milestones, including "lower is better" goals like losing weight or paying
> down debt. Interactive Home Screen widgets let you check in with one tap. Per-goal schedules
> and streaks, a plain-language pace coach ("aim for 4 km/day"), and a full check-in calendar
> and progress charts. Localized into 6 languages with an in-app language switcher.

### Shorter variant (~250 chars, if the box is small)

> A personal goal tracker built 100% with Apple frameworks and no third-party SDKs. Fully
> offline — no account, no server, no tracking. Numeric and milestone goals (including weight
> loss / debt payoff), one-tap interactive widgets, streaks, a plain-language pace coach, and
> Swift Charts progress views. 6 languages.

### One-liner (title / summary field)

> The private, offline goal tracker — one-tap widgets, streaks, and a pace coach, built entirely on Apple frameworks.

## 5. Apple technologies used  *(tick these; mention in copy if it's free text)*

- **SwiftUI** — entire UI
- **SwiftData** — local persistence, no cloud
- **WidgetKit** — 4 widget types, all three sizes, mirrored localization
- **App Intents** — interactive widgets: one-tap check-in from the Home Screen; widget paging
- **Swift Charts** — value-over-time chart with target line, 12-week activity trend, month comparison
- **StoreKit 2** — monthly / yearly subscription + lifetime unlock
- **Sign in with Apple**
- **User Notifications** — per-goal reminders + "haven't heard from you" nudges
- **App Groups** — app ↔ widget data sharing
- **Accessibility** — VoiceOver labels on every chart bar, Dynamic Type

*Not applicable (don't tick): iCloud, HealthKit, Live Activities, ARKit, Core ML / Apple
Intelligence, App Clips, SharePlay, Passkeys, CarPlay, watchOS, visionOS.*

## 6. Platforms / devices

iPhone, iOS 17 and later. (No iPad-optimized, Watch, Mac, or Vision layout — leave those
unchecked unless you add them.)

## 7. Localizations

English, Czech, German, Spanish, French, Brazilian Portuguese. In-app language switcher
independent of the system language, and the translations (with correct Czech plural forms)
carry through to the widgets.

## 8. What makes the app distinctive  *(supporting notes / "anything else" field)*

- **Offline and account-free by design.** SwiftData only; the sole outbound traffic is
  anonymous usage stats (EU servers) that contain no user content and can be turned off.
- **"Lower is better" goals are first-class** — start value + direction, so weight loss and
  debt payoff work exactly like distance or savings.
- **Schedule-aware streaks** — a goal can be daily, or a weekly/monthly quota ("3× a week");
  the streak counts against that schedule, not calendar days.
- **Pace coach in plain language** — instead of raw numbers, "aim for 4 km/day" or a projected
  finish date from your average pace so far.
- **Onboarding templates** — 9 ready-made goals (run 100 km, 10k steps, read 20 pages,
  meditate, no-spend 30 days, …) so the first goal is two taps, not a blank form.
- **Craft details**: appearance mode applied to UIKit surfaces too (keyboard, AutoFill text),
  widget localization decoupled from system language, two privacy manifests (app + extension).

## 9. Supporting materials

- Support page: <https://…/index.html>  *(fill in your GitHub Pages URL)*
- Privacy policy: <https://…/privacy.html>
- Optional: a short screen-recording of a one-tap widget check-in and the stats screen.

## 10. Contact

martin.hrbek5@gmail.com

---

## Later: the January "Habits" nomination

Separate, second nomination when you ship a Habits mode (yes/no daily actions tracked purely by
streak, on top of the existing recurrence + `StreakCalculator` engine). Submit that one late
Nov / early Dec 2026 with a January availability date, framed around New Year's resolutions.
Nominating now for 1.0.2 does not use it up — you can nominate again for every significant
release.

## Realistic expectations

A nomination is not a guarantee, even a strong one. Partial placement (a category list,
"New Apps We Love", a themed collection) is the more common outcome and still drives a
meaningful bump.
</content>
