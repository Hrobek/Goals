# Goals

Aplikace na sledování osobních cílů pro iOS. Cíle se dělí na milníky nebo se měří číselně, postup se zaznamenává check-iny a je vidět v grafech, kalendářní mřížce a widgetech na ploše.

Postavená na SwiftUI a SwiftData, **bez cloudu a bez backendu** — všechno zůstává v telefonu. To není nedodělek, ale záměr, a vysvětluje většinu rozhodnutí níž.

## Co umí

- **Cíle** s vlastními kategoriemi, jednotkami, prioritou a termínem. Sledovat se dají číselně (uběhnout 100 km, ušetřit 50 000 Kč) i odškrtáváním milníků. Číselné cíle znají počáteční hodnotu a směr „nižší je lepší", takže hubnutí i splácení dluhu fungují stejně dobře jako sbírání kilometrů.
- **Rozvrh a série** — cíl může být denní, týdenní nebo měsíční; série se počítá podle jeho vlastního rozvrhu, ne podle kalendářních dnů.
- **Obrazovka Dnes** ukazuje jen to, co je na dnešek naplánované.
- **Statistiky** — kalendářní mřížka check-inů, čárový graf hodnoty v čase s cílovou linkou, srovnání měsíců a slovní odhad tempa („miř na 4 km denně", odhad data dokončení).
- **Widgety** ve třech druzích a třech velikostech, s tlačítkem na jedno klepnutí přímo z plochy (AppIntents) a listováním, když se cíle nevejdou.
- **Připomínky** per cíl, plus automatické „dlouho ses neozval" po 3 a 10 dnech ticha.
- **Šest jazyků** — čeština, angličtina, španělština, němčina, francouzština, brazilská portugalština. Jazyk je přepínač v aplikaci, nezávislý na systému, a zrcadlí se i do widgetů.
- **Přihlášení** přes Apple, Google, nebo e-mailem a heslem — lokálně, jako identita v aplikaci.
- **Zdarma** tři aktivní cíle; Pro odemyká neomezený počet, pokročilé statistiky a Pro widgety.

## Požadavky

| | |
|---|---|
| Xcode | 26 nebo novější (iOS 26.5 SDK) |
| Cílová platforma | iOS 26.5 |
| Závislosti | **žádné** — čistý SwiftUI, SwiftData, StoreKit 2, WidgetKit |

## Sestavení

```bash
git clone <adresa-repozitáře>
cd Goals
open Goals.xcodeproj
```

Vyberte schéma **Goals** a spusťte. Bez dalšího nastavení běží všechno kromě přihlášení Googlem a nákupů.

### Podpisování

Projekt má v sobě App Group `group.com.hrobek.goals` a Přihlášení přes Apple. Pro běh na skutečném zařízení nastavte v Xcode svůj tým a **změňte identifikátory** — App Group i oba bundle ID (`com.hrobek.goals` a `com.hrobek.goals.GoalsWidget`) jsou vázané na účet autora. App Group musí být zapsaná v obou cílech, jinak widgety neuvidí data aplikace.

### Přihlášení Googlem (volitelné)

Postavené bez SDK — OAuth 2.0 s PKCE přes `ASWebAuthenticationSession`, protože kvůli jednomu tlačítku nemá smysl táhnout do projektu celou knihovnu.

1. V Google Cloud Console vytvořte OAuth klienta typu **iOS**.
2. Stažený `client_*.apps.googleusercontent.com.plist` vložte do složky **`Goals/`** — ne do kořene repozitáře, tam ho synchronizované složky Xcode nenajdou.
3. V `GoalsInfo.plist` zkontrolujte, že `CFBundleURLSchemes` odpovídá vašemu obrácenému client ID.

Plist je v `.gitignore`. Pro nativní PKCE klienty to není tajemství, ale patří ke konkrétnímu účtu, ne do repozitáře. Bez něj se tlačítko Googlu jen neobjeví; zbytek aplikace funguje.

### Nákupy

Testují se lokálně přes `Goals.storekit`, bez App Store Connect: v editoru schématu → Run → Options → StoreKit Configuration vyberte tento soubor. Jsou v něm tři produkty (měsíčně, ročně, jednorázově napořád) i s překlady, které se ukazují v systémové potvrzovací tabulce.

Ceny v tom souboru jsou orientační placeholdery — ostré se nastavují až v App Store Connect.

## Struktura

```
Goals/          aplikace — obrazovky, přihlášení, nákupy, zpětná vazba
GoalsWidget/    rozšíření s widgety a jejich AppIntents
Shared/         model, výpočty a texty sdílené aplikací i widgety
docs/           stránka podpory a zásady soukromí (GitHub Pages)
```

`Shared/` je v obou cílech, takže se widget dostane k témuž modelu i k témuž překladu. Xcode používá synchronizované složky (`PBXFileSystemSynchronizedRootGroup`), takže **přidaný soubor se do cíle zapojí sám** podle toho, ve které složce leží — do `project.pbxproj` není potřeba sahat.

## Za zmínku

Několik míst, kde řešení není zřejmé na první pohled a stojí za to je nerozbít:

- **Množná čísla se musí volat s `locale:`, ne jen s `bundle:`.** Samotný `.lproj` balík neříká, jaký je to jazyk, a Foundation pak vybírá tvary podle anglických pravidel — čeština s 1/2–4/5+ tvary tím tiše rozbije.
- **Nárok na Pro se zrcadlí do App Group**, protože widget se nemá koho zeptat — StoreKit v rozšíření nedosáhne na účet.
- **Volba vzhledu se nastavuje dvakrát**: `preferredColorScheme` pokryje jen to, co kreslí SwiftUI. Co si kreslí UIKit sám (klávesnice, text doplněný z AutoFill) čte styl okna, a okno ponechané ve světlém režimu maluje tmavý text na tmavý podklad.
- **Analytika je hand-rolled**, jeden POST na TelemetryDeck bez SDK. Klíče parametrů jsou uzavřený `enum`, takže odeslání obsahu uživatele nehlídá dobrý úmysl, ale překladač. Všechno prochází jednou funkcí.
- **Privacy manifesty jsou dva** — aplikace i rozšíření mají vlastní, protože widget jde do App Store jako samostatný balík.

## Soukromí

Aplikace nemá server. Ven odchází jedině anonymní statistika používání (TelemetryDeck, servery v EU), kterou jde vypnout v Nastavení, a neobsahuje nic, co uživatel napsal. Podrobně v [zásadách ochrany soukromí](docs/privacy.html).

## Licence

Zatím nestanovena — bez licence platí výchozí autorské právo a dílo není volné k užití.
