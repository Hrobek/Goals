# Pricing

## What customers pay

Set in App Store Connect, not in this repo. The base price is **USD**; Apple generates every other
storefront from it, and two of those are overridden by hand because the generated numbers don't land
on the figures we want:

| | USD (base) | CZK (manual) | EUR (manual) |
|---|---|---|---|
| Monthly | $3.99 | 99 Kč | 3,99 € |
| Yearly | $27.99 | 699 Kč | 27,99 € |
| Lifetime | $39.99 | 999 Kč | 39,99 € |

Everywhere else Apple's own conversion applies — that's the point of a base price, and those
storefronts don't need looking after.

The yearly plan is ~41 % cheaper than twelve monthly payments in all three. The paywall's savings
badge works the percentage out from whatever prices StoreKit hands back rather than from a number
written down here, so it stays truthful in the storefronts Apple derived too.

## Testing other currencies locally

A `.storekit` file holds one price per product in one storefront's currency, so there's one package
per currency:

| Package | Storefront |
|---|---|
| `Goals.storekit` | USA — the one the scheme uses |
| `Goals-CZK.storekit` | CZE |
| `Goals-EUR.storekit` | DEU |

To run against one of the others: Product → Scheme → Edit Scheme… → Run → Options → **StoreKit
Configuration**. If a package isn't in the list, drag it into the project navigator first (it only
needs to be in the project, not in a target).

Products are cached per configuration, so if old prices are still showing after a switch, delete the
app from the simulator and run again.

## Careful with Xcode

Xcode rewrites an open `.storekit` file from its own in-memory copy when it saves, which silently
undoes edits made outside it. Close the file's editor tab before editing these by hand.
