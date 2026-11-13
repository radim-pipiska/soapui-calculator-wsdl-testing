# REST, SOAP a messaging očima testera

REST chování je z testování Vacation API, SOAP chování pozorováno na veřejném Calculatoru, messaging je z cvičení bez reálného brokeru.

| | REST | SOAP | Messaging |
| :--- | :--- | :--- | :--- |
| **Kontrakt (kde je popsaný, jak se jmenuje)** | OpenAPI (Swagger) | WSDL + XSD | AsyncAPI |
| **Formát zprávy** | Obvykle JSON (příp. XML) | XML | Dle kontraktu (obvykle JSON, Avro, Protobuf) |
| **Jak se pozná úspěch a jak chyba** | **Úspěch:** HTTP 2xx (200, 201, 204) + validní payload.<br>**Chyba:** HTTP 4xx / 5xx nebo neplatná struktura dat. [OVĚŘIT] | **Úspěch:** HTTP 200 OK + validní XML bez `<Fault>`, odpovídající byznys logice.<br>**Chyba:** HTTP 500 + element `<soap:Fault>` (`faultcode` soap:Client / soap:Server). *Jde o SOAP 1.1 a o pozorování na Calculatoru.* | **Úspěch:** Potvrzení brokerem (ACK) + zpracování konzumentem (změna stavu).<br>**Chyba:** NACK, odmítnutí zprávy nebo její pád do DLQ (Dead Letter Queue). |
| **Co test kromě statusu musí ověřit** | Strukturu JSONu (schéma), konkrétní klíče, datové typy, hodnoty polí a uložení dat v DB. | Strukturu XML proti XSD, konkrétní hodnoty v elementech pomocí XPath Match. *Moje vlastní nálezy ale ukazují, že Schema Compliance a SOAP Response zůstaly zelené i na Faultu a u špatného namespace. XSD je tedy nutná podmínka, ne důkaz úspěchu. Rozhoduje aserce na hodnotu (XPath) spolu s „není Fault“.* | **Pro aserci:** Změnu stavu v databázi nebo odeslání navazující zprávy.<br>**Pro vyšetřování:** Aplikační logy. |
| **Jedna past z vlastní zkušenosti v těchto týdnech** | Testování proti *staré proměnné prostředí.* Další pastí byla špatně zapsaná proměnná *{{PersonId}}*. V Postman je Case-sensitivní, v důsledku záměny proměnné *PersonId vs. personId* později v runneru byly testy **falešně zelené** (prošly, přestože něco bylo špatně). | Prázdný **intB** (u Divide). **HTTP 500** i **SOAP Fault** prošly i u **chyby klienta** a rozlišil to až **faultcode**. Další pastí byla aserce na číslo 12+prázdný řádek v XPath Match. | Past „z cvičení“ AI: **zelená aserce na 202 nic nedokazuje**, nebo **pevná pauza**, kde AI si číslo 5 sekund vymyslela a já jsem to správně zpochybnil. |
