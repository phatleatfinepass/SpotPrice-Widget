# Support

## Before reporting a problem

1. Open **Finland Electricity Rates** and press Refresh.
2. Confirm the Mac is connected to the internet.
3. Use **Danger Zone → Reset Widget Data…** to clear rebuildable app data and request fresh WidgetKit timelines.
4. Close and reopen the widget gallery after installing an update.
5. Remove and add the affected widget again if WidgetKit is showing an old snapshot.

Grid-emissions data normally arrives through the project’s public read-only cache and requires no customer API key. If the cache is temporarily stale or unavailable, the renewable forecast remains independent and should continue to update.

## macOS blocks the first launch

The free direct release is ad-hoc signed and not Apple-notarized. Try opening **Finland Electricity Rates** once, then open **System Settings → Privacy & Security**, confirm that the blocked app is **Finland Electricity Rates**, and select **Open Anyway**. Do not disable Gatekeeper or remove quarantine protection.

## Report a bug

Open a [GitHub issue](https://github.com/phatleatfinepass/SpotPrice-Widget/issues) with:

- macOS or iOS version
- app version from the About window
- widget name and size
- what you expected and what appeared
- a screenshot with credentials and personal information removed

Never post API keys, passwords, tokens, or authentication headers.
