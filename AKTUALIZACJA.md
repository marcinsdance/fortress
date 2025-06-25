# Instrukcja Aktualizacji Fortress na VPS Google Cloud

## 🚀 Bezpieczna Aktualizacja z Zachowaniem Aplikacji

Ta instrukcja pozwoli Ci bezpiecznie zaktualizować Fortress na Twoim VPS Google Cloud bez przerywania działania aplikacji internetowych.

## ⚠️ Ważne Informacje

- **Zero Downtime**: Aplikacje będą działać przez cały czas aktualizacji
- **Backup Automatyczny**: System automatycznie utworzy backup przed aktualizacją
- **Rollback**: Możliwość szybkiego powrotu do poprzedniej wersji
- **Zachowanie Danych**: Wszystkie konfiguracje i dane aplikacji pozostaną nietknięte

## 📋 Wymagania

- Root lub sudo dostęp do serwera
- Działający system Fortress
- Połączenie z internetem
- Co najmniej 2GB wolnego miejsca na dysku

## 🔄 Proces Aktualizacji

### Krok 1: Przygotowanie Skryptów

Skopiuj skrypty aktualizacji na swój serwer VPS:

```bash
# Zaloguj się do VPS
ssh root@TWOJ_VPS_IP

# Utwórz katalog na skrypty
mkdir -p /opt/fortress-update

# Skopiuj skrypty (możesz użyć scp, rsync lub git)
# Przykład z git:
cd /tmp
git clone https://github.com/marcinsdance/fortress.git
cp fortress/scripts/fortress-*.sh /opt/fortress-update/
chmod +x /opt/fortress-update/*.sh
```

### Krok 2: Sprawdzenie Aktualnego Stanu

```bash
# Sprawdź status aplikacji
fortress app list

# Sprawdź działające kontenery
docker ps

# Sprawdź aktualną wersję Fortress
fortress --version
```

### Krok 3: Symulacja Aktualizacji (Opcjonalne)

Zalecane jest wykonanie symulacji przed rzeczywistą aktualizacją:

```bash
# Uruchom symulację aktualizacji
/opt/fortress-update/fortress-update.sh --dry-run

# Sprawdź czy nie ma błędów
echo $?
```

### Krok 4: Wykonanie Backup'u

```bash
# Automatyczny backup (wykonuje się też podczas aktualizacji)
/opt/fortress-update/fortress-backup.sh

# Sprawdź czy backup został utworzony
ls -la /opt/fortress/backups/system/
```

### Krok 5: Aktualizacja Fortress

```bash
# Standardowa aktualizacja z głównej gałęzi
/opt/fortress-update/fortress-update.sh

# Lub z określonej gałęzi/wersji
/opt/fortress-update/fortress-update.sh --branch main

# Wymuś aktualizację (gdy wersje są takie same)
/opt/fortress-update/fortress-update.sh --force
```

### Krok 6: Weryfikacja Po Aktualizacji

```bash
# Sprawdź nową wersję
fortress --version

# Sprawdź status aplikacji
fortress app list
fortress app status NAZWA_APLIKACJI

# Sprawdź logi systemowe
docker logs fortress_traefik
```

## 🔧 Opcje Zaawansowane

### Aktualizacja z Określonej Gałęzi

```bash
# Aktualizacja z gałęzi develop
/opt/fortress-update/fortress-update.sh --branch develop

# Aktualizacja z określonego tagu
/opt/fortress-update/fortress-update.sh --branch v2.0.0
```

### Aktualizacja Bez Backup'u (Niezalecane)

```bash
/opt/fortress-update/fortress-update.sh --no-backup
```

### Wymuszona Aktualizacja

```bash
# Gdy chcesz zaktualizować mimo tej samej wersji
/opt/fortress-update/fortress-update.sh --force
```

## 🚨 Rozwiązywanie Problemów

### Problem: Aplikacje Nie Działają Po Aktualizacji

```bash
# Sprawdź logi aplikacji
fortress logs NAZWA_APLIKACJI

# Restart aplikacji
cd /opt/fortress/apps/NAZWA_APLIKACJI
docker compose restart

# Lub użyj komendy fortress
fortress app restart NAZWA_APLIKACJI
```

### Problem: Traefik Nie Uruchamia Się

```bash
# Sprawdź logi Traefik
docker logs fortress_traefik

# Restart Traefik
cd /opt/fortress/proxy
docker compose down
docker compose up -d
```

### Problem: Problemy z SSL

```bash
# Sprawdź certyfikaty
fortress ssl status TWOJA_DOMENA

# Odnów certyfikaty
fortress ssl renew TWOJA_DOMENA
```

## 🔄 Rollback - Powrót do Poprzedniej Wersji

Jeśli napotkasz problemy, możesz szybko wrócić do poprzedniej wersji:

```bash
# Znajdź najnowszy backup
ls -la /opt/fortress/backups/system/

# Przywróć backup (zastąp TIMESTAMP właściwą datą)
cd /opt/fortress/backups/system/
tar -xzf fortress_backup_TIMESTAMP.tar.gz

# Zatrzymaj usługi
docker stop fortress_traefik

# Przywróć pliki
cp -r fortress_backup_TIMESTAMP/bin/* /opt/fortress/bin/
cp -r fortress_backup_TIMESTAMP/commands/* /opt/fortress/commands/
cp -r fortress_backup_TIMESTAMP/proxy/* /opt/fortress/proxy/

# Ustaw uprawnienia
chmod +x /opt/fortress/bin/fortress
ln -sf /opt/fortress/bin/fortress /usr/local/bin/fortress

# Restart usług
cd /opt/fortress/proxy
docker compose up -d
```

## 📊 Monitoring Po Aktualizacji

### Sprawdzenie Zdrowia Systemu

```bash
# Status wszystkich aplikacji
fortress app list

# Metryki zasobów
fortress resources show

# Dashboard monitorowania (jeśli włączony)
fortress monitor dashboard
```

### Sprawdzenie Logów

```bash
# Logi aplikacji
fortress logs NAZWA_APLIKACJI --follow

# Logi systemowe
journalctl -u docker -f
```

## 🔒 Bezpieczeństwo

### Po Aktualizacji Sprawdź:

```bash
# Status firewall
fortress firewall status

# Skanowanie bezpieczeństwa
fortress security scan

# Aktualizacja fail2ban (jeśli używane)
fail2ban-client status
```

## 📝 Notatki

### Co Zostaje Zachowane:
- ✅ Wszystkie aplikacje i ich dane
- ✅ Bazy danych (PostgreSQL, Redis)
- ✅ Certyfikaty SSL
- ✅ Konfiguracje aplikacji
- ✅ Konfiguracje Traefik
- ✅ Ustawienia firewall

### Co Zostaje Zaktualizowane:
- 🔄 Pliki wykonywalne Fortress
- 🔄 Skrypty komend
- 🔄 Narzędzia pomocnicze
- 🔄 Wersja systemu

## 🆘 Wsparcie

Jeśli napotkasz problemy:

1. **Sprawdź logi**: `fortress logs --system`
2. **Przywróć backup**: Użyj instrukcji rollback powyżej
3. **Kontakt**: Zgłoś problem na [GitHub Issues](https://github.com/marcinsdance/fortress/issues)

## ✅ Checklist Aktualizacji

- [ ] Utworzony backup systemu
- [ ] Sprawdzony status aplikacji przed aktualizacją
- [ ] Wykonana symulacja aktualizacji
- [ ] Przeprowadzona aktualizacja
- [ ] Zweryfikowane działanie aplikacji
- [ ] Sprawdzone logi systemowe
- [ ] Przetestowane domeny i SSL
- [ ] System monitorowania działa poprawnie

---

**Czas wykonania**: ~15-30 minut  
**Czas przestoju**: 0 minut dla aplikacji  
**Wymagane umiejętności**: Podstawowa znajomość Linux i Docker