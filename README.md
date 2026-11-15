# GR Formela

Aplikacja tylko dla gospodarstwa Formela Adam. Kolejna ferma = kopia tych plików
z własną nazwą, ikoną i osobnym projektem Firebase.

## Pliki
- `index.html` – cała aplikacja
- `manifest.json`, `sw.js`, `icon-*.png`, `apple-touch-icon.png`, `favicon-32.png` – instalacja na telefonie/komputerze (PWA)
- `firestore.rules` – reguły dostępu do bazy
- `infodex_diagnostyka.sql` – zapytanie na komputer klienta (następna wizyta)

## Szybki test bez Firebase
Otwórz `index.html` w przeglądarce (dwuklik). Aplikacja działa w **trybie lokalnym**:
dane zapisują się tylko w tej przeglądarce. Wgraj plik z SOL
w zakładce *Próbne doje*, potem przydziel krowy w zakładce *Grupy*.

## Uruchomienie na Firebase (dostęp z telefonu i komputera)
1. W konsoli Firebase utwórz **nowy projekt** dla tej fermy (np. `gr-formela`).
2. *Firestore Database* → Utwórz bazę (region europe-central2 lub europe-west).
3. *Authentication* → Metoda logowania → włącz **Google**.
4. *Ustawienia projektu* → Twoje aplikacje → dodaj aplikację Web → skopiuj `firebaseConfig`
   i wklej go na górze skryptu w `index.html` (w miejsce `WKLEJ...`).
5. W `firestore.rules` wpisz swój adres e-mail Google, wklej reguły w
   *Firestore → Reguły* i opublikuj.
6. Wgraj pliki na Firebase Hosting tak samo jak Stuchowo
   (`firebase init hosting`, potem `firebase deploy`).
7. Jeśli testowałeś w trybie lokalnym: *Ustawienia → Pobierz kopię (JSON)* przed
   podmianą konfiguracji, a po zalogowaniu *Wczytaj kopię*.

Po każdej zmianie `index.html` podbij `CACHE_NAME` w `sw.js` (grformela-v1 → grformela-v2),
żeby telefony pobrały nową wersję.

## Logowanie i dostęp (krok po kroku)
Każda osoba wchodzi **własnym hasłem** (bez e-maila). Hasło wskazuje konto i to, które zakładki widzi.
Telefon pamięta zalogowanie – hasło wpisuje się raz. Dostępem zarządza twórca w zakładce **Dostęp**:
dodaje osoby i agenta, zaznacza zakładki, daje albo zabiera prawo zapisu, blokuje i nadaje nowe hasła.
Haseł nigdzie nie zapisujemy, ani w kodzie, ani w bazie.

Kolejność jest ważna. Aplikacja bez opublikowanych reguł nie pokaże kodu konta (zobaczysz „Brak dostępu”).

1. Konsola Firebase → **Authentication → Metoda logowania**: włącz **E-mail/hasło**.
2. **Authentication → Ustawienia → Autoryzowane domeny**: sprawdź, że jest `piterds7-blip.github.io`
   (adresy `…web.app` i `…firebaseapp.com` są tam od początku).
3. **Firestore → Reguły**: wklej zawartość `firestore.rules` i kliknij **Opublikuj**.
   Od tej chwili stary agent z obory nie wyśle danych (baza jest zamknięta). Dane zostają w Infodexie,
   a nowy agent dośle ostatnie 10 dni (przy dłuższej przerwie uruchom `EKSPORT_calosc.bat`).
4. W aplikacji: rozwiń „Pierwsze uruchomienie (tylko twórca)”, wpisz własne hasło (min. 10 znaków) i kliknij
   „Utwórz konto twórcy”. Aplikacja pokaże **kod konta** (skopiuj go, nie przepisuj).
5. **Firestore → Dane**: kolekcja `uzytkownicy` **na samym szczycie** (nie w `farms`), dokument o **ID = kod konta**, pola:
   `rola` = `admin`, `aktywny` = `true` (boolean), `imie` = Twoje imię. Aplikacja od razu pokaże zakładkę **Dostęp**.
6. W zakładce **Dostęp** dodaj osoby i „Komputer w oborze (agent)”. Konta zakładaj tylko tu, nie w konsoli Firebase.
7. Na komputerze w oborze uruchom **USTAW_KONTO.bat** (hasło agenta), potem **EKSPORT_ostatnie_dni.bat** – ma skończyć się napisem GOTOWE.

Hasła innym osobom zmienia twórca (Dostęp → „Nowe hasło”). Własne hasło twórca zmienia przyciskiem
„Zmień moje hasło” (Dostęp albo literka w nagłówku). Na telefonie przy wpisywaniu użyj ikony oka 👁, żeby zobaczyć wpisany tekst.

Co sprawdza baza: brak konta lub blokada = brak dostępu; „Może zmieniać dane” = zapis, bez tego tylko podgląd;
agent może tylko wysyłać dane z Infodexu. Zakładki ukrywa aplikacja (osoba z dostępem do odczytu technicznie
może odczytać wszystkie dane gospodarstwa, nie tylko te z widocznych zakładek).

## Agent z obory (`agent/`)
- `ZAINSTALUJ.bat` – pierwsza instalacja: konto agenta, pierwsza wysyłka, harmonogram 06:00 i 17:00.
- `USTAW_KONTO.bat` – hasło agenta (z zakładki Dostęp). Zapisuje się zaszyfrowane przez Windows w `%USERPROFILE%\GRFormela`.
- `EKSPORT_ostatnie_dni.bat`, `EKSPORT_calosc.bat` – wysyłka ręczna; `EKSPORT_do_pliku.bat` – awaryjnie plik na pendrive.
- Pliki z danymi (`*.json`, log, stan, konto) nie trafiają do repozytorium (`.gitignore`).

## Co jest w aplikacji
- **Grupy**: tablica Nieprzypisane / Grupa 1 / Grupa 2 / Zasuszone. Na komputerze
  przeciąganie myszą, na telefonie dotknięcie krowy i przycisk grupy. Tryb
  zaznaczania wielu krów. Podpowiedzi według dnia laktacji, wpisu „zasuszenie”
  z próbnego doju, planowanej daty wycielenia i nowego wycielenia. Przypinanie,
  historia przesunięć, wydruk listy grup.
- **Dziś**: ruja na górze, pod nią zwijane sekcje: krowy do sprawdzenia, świeże krowy (21 dni po wycieleniu), mleko stada, kalendarz.
- **Stado**: wyniki rozrodu (12 miesięcy, skuteczność buhajów), tabela z sortowaniem, filtrami i eksportem do Excela; karta krowy.
- **Próbne doje**: import pliku z SOL z podglądem przed zapisem, historia
  miesięcy, analiza według grup (tabela średnich, listy krów do sprawdzenia:
  T/B, LKS, mocznik, Sket; wykresy mocznik–białko i kg–dzień laktacji, trend).
- **Ustawienia**: progi grup i normy analizy, kopia JSON.

## Następne kroki
1. Wynik `infodex_diagnostyka.sql` z komputera klienta.
2. Agent synchronizujący Infodex → Firebase (numer respondera, zdarzenia, dzienne mleko).
3. Widoki danych z Infodexa w karcie krowy i na wykresach.
