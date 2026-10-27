# SoapUI Assertions: Negativní scénář Dělení nulou

**Prohlášení o předpokladech:**
Tato konfigurace vychází výhradně z aktuálně pozorovaného chování testovaného serveru (HTTP 500 na http://www.dneonline.com/calculator.asmx). Předpokládáme, že rozhraní při chybě dělení nulou generuje standardní chybový stav SOAP 1.1 (`soap:Server`) a vnitřní výjimku `.NET` typu `System.OverflowException` balí do obecné `SoapException`. Pokud by vývojáři v budoucí verzi změnili chování aplikace (např. na klientskou chybu `soap:Client` nebo upravili text výjimky), testy budou oprávněně padat.

---

## 1. Validace elementu `<faultcode>`

Tato validace ověřuje, že server klasifikoval chybu na své straně.

* **XPath Expression:**
  ```xpath
  declare namespace soap='http://schemas.xmlsoap.org/soap/envelope/';
  //soap:Envelope/soap:Body/soap:Fault/faultcode
  ```
* **Expected Result:**
  ```text
  soap:Server
  ```

---

## 2. Validace elementu `<faultstring>`

Tato validace ověřuje přítomnost stabilních textových řetězců chybové zprávy, přičemž bezpečně ignoruje proměnlivé detaily (jako jsou absolutní cesty k souborům na disku nebo čísla řádků kódu).

* **XPath Expression:**
  ```xpath
  declare namespace soap='http://schemas.xmlsoap.org/soap/envelope/';
  //soap:Envelope/soap:Body/soap:Fault/faultstring
  ```
* **Expected Result:** (*Ujistěte se, že máte **zaškrtnuté** políčko **Allow Wildcards***)
  ```text
  *Server was unable to process request.*System.OverflowException: Arithmetic operation resulted in an overflow*
  ```

---

## 3. Průvodce „Test the Tester“ (Simulace selhání)

Abyste měli stoprocentní jistotu, že vaše validace nejsou tzv. *false positives* (že neprojdou zelené i v případě, kdy systém vrátí něco špatně), proveďte následující ověřovací kroky:

### Pro validaci `faultcode`:
* **Simulace úpravou očekávání:** Otevřete nastavení této konkrétní XPath validace a změňte pole **Expected Result** ze `soap:Server` na `soap:Client`. Klikněte na tlačítko **Test**. Validace *musí zčervenat* a selhat na neshodě řetězců.
* **Simulace úspěšným požadavkem:** Změňte parametry v Requestu na platné hodnoty (např. `intA = 2`, `intB = 2`) a odešlete požadavek. Server vrátí úspěšnou odpověď 200 OK bez chybového těla. Validace *musí selhat* s chybou `Exception: Missing content for xpath`, protože prvek `faultcode` v XML vůbec neexistuje.

### Pro validaci `faultstring`:
* **Simulace úpravou očekávání:** Změňte pole **Expected Result** tak, aby hledalo jinou výjimku, například: `*System.NullReferenceException*`. Klikněte na tlačítko **Test**. Validace *musí selhat*, protože regulární výraz (wildcard) nenajde v textu shodu.
* **Simulace úspěšným požadavkem:** Stejně jako v prvním případě odešlete validní požadavek na dělení `2 / 2`. Vzhledem k tomu, že úspěšná odpověď neobsahuje strukturu `<soap:Fault>`, XPath výraz v odpovědi nenajde cílový element a validace okamžitě selže, což potvrdí její funkčnost.