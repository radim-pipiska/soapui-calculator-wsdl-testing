
| | REST | SOAP | Messaging |
| :--- | :--- | :--- | :--- |
| **Kontrakt (kde je popsaný, jak se jmenuje)** | OpenAPI (Swagger) | WSDL + XSD | AsyncAPI |
| **Formát zprávy** | Obvykle JSON (příp. XML) | XML | Dle kontraktu (obvykle JSON, Avro, Protobuf) |
| **Jak se pozná úspěch a jak chyba** | **Úspěch:** HTTP 2xx (200, 201, 204) + validní payload.<br>**Chyba:** HTTP 4xx / 5xx nebo neplatná struktura dat. | **Úspěch:** HTTP 200 OK + validní XML bez `<Fault>`, odpovídající byznys logice.<br>**Chyba:** HTTP 500 + element `<soap:Fault>` (`faultcode` soap:Client / soap:Server). | **Úspěch:** Potvrzení brokerem (ACK) + zpracování konzumentem (změna stavu).<br>**Chyba:** NACK, odmítnutí zprávy nebo její pád do DLQ (Dead Letter Queue). |
| **Co test kromě statusu musí ověřit** | Strukturu JSONu (schéma), konkrétní klíče, datové typy, hodnoty polí a uložení dat v DB. | Strukturu XML proti XSD, konkrétní hodnoty v elementech pomocí XPath Match. | **Pro aserci:** Změnu stavu v databázi nebo odeslání navazující zprávy.<br>**Pro vyšetřování:** Aplikační logy. |
| **Jedna past z tvé vlastní zkušenosti v těchto týdnech** | *(Doplň svou zkušenost z Postmanu – např. zapomenutá hlavička Content-Type, testování proti staré proměnné prostředí nebo 200 OK s chybou v těle.)* | Dělení prázdným řetězcem (`Divide intB ""`) a aserce na číslo 12+prázdný řádek v XPath Match. | Duplicita v logu, *dva záznamy se stejnými klíči jako correlationID a Status* nebo když test selže s hláškou *Nedokončenov limitu* |
