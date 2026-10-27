# SoapUI Aserce pro negativní scénář "Dělení nulou" (Operace Divide)

Jako seniorní QA automatizér vám přináším ucelenou a přehlednou konfiguraci asercí na základě reálné chybové odpovědi služby `Calculator.asmx`. Vzhledem k absenci oficiální byznysové specifikace vycházíme z pozorovaného chování systému.

---

## 1. Aserce na chybový kód (`<faultcode>`)

Tato aserce ověřuje, zda server jednoznačně klasifikoval chybu jako selhání na straně serveru.

### Konfigurace v SoapUI:
* **Typ aserce:** XPath Match
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

## 2. Aserce na chybovou zprávu (`<faultstring>`) s využitím Wildcards

Abychom odfiltrovali nestabilní části (cesty k souborům na disku `G:\...` a konkrétní čísla řádků v kódu), které se mohou s každým novým releasem změnit, použijeme zástupné znaky.

### Konfigurace v SoapUI:
* **Typ aserce:** XPath Match
* **XPath Expression:**
  ```xpath
  declare namespace soap='http://schemas.xmlsoap.org/soap/envelope/';
  //soap:Envelope/soap:Body/soap:Fault/faultstring
  ```
* **Expected Result:**
  ```text
  *Server was unable to process request.*System.OverflowException: Arithmetic operation resulted in an overflow.*
  ```
* **Důležité nastavení:** V konfiguračním okně aserce **musíte zaškrtnout políčko "Allow Wildcards"**.

> **Poznámka ke konfiguraci:** První hvězdička pokryje případný úvodní text před "Server was...", prostřední hvězdička bezpečně pohltí spojovací text `.---> ` a zejména znaky konce řádku (new lines), poslední hvězdička pak odřízne celý zbývající stack trace.

---

## 3. Manuál „Test the Tester“ (Ověření funkčnosti asercí)

Provádí se za účelem vyloučení falešně pozitivních výsledků, abychom měli stoprocentní jistotu, že aserce zachytí neočekávané stavy.

### Testování Aserce 1 (`faultcode`):
1. **Simulace selhání změnou Expected Result:** Změňte v aserci hodnotu v poli *Expected Result* z `soap:Server` na `soap:Client`. Spusťte krok. Aserce **musí selhat** s chybou informující o tom, že očekávala `soap:Client`, ale obdržela `soap:Server`. Následně vraťte hodnotu zpět.
2. **Simulace selhání změnou vstupu (2 / 2):** Odešlete validní požadavek (např. dělení `4 / 2`). Server vrátí úspěšné XML s elementem `<DivideResult>2</DivideResult>`. Element `<faultcode>` v odpovědi vůbec nebude existovat. Aserce **musí selhat** na chybě `XPath contains no matches`.

### Testování Aserce 2 (`faultstring`):
1. **Simulace selhání změnou Expected Result:** Upravte v poli *Expected Result* text na masku obsahující např. `*System.DivideByZeroException*`. Spusťte krok. Protože se v reálné odpovědi nachází `OverflowException`, divoká karta text netrefí a aserce **musí selhat**. Následně vraťte původní masku s `System.OverflowException`.
2. **Simulace selhání změnou vstupu (2 / 2):** Odešlete validní požadavek (např. `4 / 2`). Úspěšná odpověď neobsahuje chybové elementy. Aserce **musí okamžitě selhat** na neexistenci XPath cesty (`XPath contains no matches`), což potvrzuje, že aserce nepropustí úspěšný průchod jako chybový stav.
