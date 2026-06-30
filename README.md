# PIXELWISE

Vorgehen, um Projektarbeit umzusetzen:

--- Repo klonen ---
git clone https://github.com/Foxxx888/pixelwise.git

--- in Ordner gehen und dort den Tag öffnen ---
cd pixelwise
git checkout v05-PA-Fuchs-Marius

--- setup-server.sh ausführen ---
bash setup-server.sh

--- In PostSQL Umgebung wechseln ---
sudo -i -u postgres
psql 

--- Nun den Anweisungen der SQL Datei "database/all_tests.sql" folgen ---

