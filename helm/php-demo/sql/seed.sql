-- BPA-Demo Seed Data
-- Brands, capabilities, 150 products (50 × Shelly, SonOff, Tuya), demo users
-- Password format $SETUP$<plain> is upgraded to bcrypt on first login by auth.php
SET NAMES utf8mb4;

-- ── Brands ────────────────────────────────────────────────────────────────────
INSERT INTO brands (id, name, slug, color, description) VALUES
(1, 'Shelly',  'shelly',  '1a73e8', 'Austrian brand – compact WiFi, Matter and Bluetooth smart home devices'),
(2, 'SonOff',  'sonoff',  'd32f2f', 'ITEAD brand – affordable WiFi and Zigbee smart home controllers'),
(3, 'Tuya',    'tuya',    'f57c00', 'Global IoT platform – WiFi, Zigbee, Matter and Bluetooth smart devices');

-- ── Capabilities ──────────────────────────────────────────────────────────────
INSERT INTO capabilities (id, name, slug, color) VALUES
(1, 'WiFi',      'wifi',      '2e7d32'),
(2, 'Zigbee',    'zigbee',    '00695c'),
(3, 'Matter',    'matter',    '6a1b9a'),
(4, 'Z-Wave',    'z-wave',    '01579b'),
(5, 'Bluetooth', 'bluetooth', '1a237e'),
(6, 'Tuya',      'tuya',      'e65100');

-- ── Shelly Products (id 1-50) ─────────────────────────────────────────────────
INSERT INTO products (id, brand_id, name, slug, description, price, stock) VALUES
( 1, 1, 'Shelly Plus 1',           'shelly-plus-1',           'Single-channel WiFi smart relay, fits behind any switch.',         12.90,  80),
( 2, 1, 'Shelly Plus 1PM',         'shelly-plus-1pm',         'WiFi relay with real-time power metering, 1-channel.',             14.90,  75),
( 3, 1, 'Shelly Plus 2PM',         'shelly-plus-2pm',         'Dual WiFi relay with individual power metering per channel.',      19.90,  60),
( 4, 1, 'Shelly Plus i4',          'shelly-plus-i4',          '4-input WiFi device for wired buttons and sensors.',               18.90,  55),
( 5, 1, 'Shelly Plus Plug S',      'shelly-plus-plug-s',      'Compact EU WiFi smart plug with power monitoring.',                14.90,  90),
( 6, 1, 'Shelly Plus Plug IT',     'shelly-plus-plug-it',     'Italian-standard WiFi smart plug with energy monitoring.',         14.90,  40),
( 7, 1, 'Shelly Plus Plug UK',     'shelly-plus-plug-uk',     'UK-standard WiFi smart plug with energy monitoring.',              14.90,  35),
( 8, 1, 'Shelly Plus H&T',         'shelly-plus-ht',          'Battery WiFi sensor reporting temperature and humidity.',          22.90,  70),
( 9, 1, 'Shelly Plus Smoke',       'shelly-plus-smoke',       'WiFi photoelectric smoke detector with alarm relay output.',       29.90,  45),
(10, 1, 'Shelly Pro 1',            'shelly-pro-1',            'DIN-rail WiFi relay, 1-channel, for professional installations.',  24.90,  50),
(11, 1, 'Shelly Pro 2',            'shelly-pro-2',            'DIN-rail dual WiFi relay for load and shutter control.',           34.90,  45),
(12, 1, 'Shelly Pro 4PM',          'shelly-pro-4pm',          'DIN-rail 4-channel WiFi relay with per-channel power metering.',   69.90,  30),
(13, 1, 'Shelly Pro 3',            'shelly-pro-3',            'DIN-rail 3-channel WiFi relay for lighting and HVAC.',             44.90,  35),
(14, 1, 'Shelly Pro 3EM',          'shelly-pro-3em',          '3-phase WiFi energy meter, 120A per phase, DIN-rail mount.',       89.90,  25),
(15, 1, 'Shelly 1L',               'shelly-1l',               'Single WiFi relay for no-neutral switch boxes.',                    9.90,  85),
(16, 1, 'Shelly 1PM Mini Gen3',    'shelly-1pm-mini-gen3',    'Ultra-compact WiFi relay with power metering, Gen3 chip.',         11.90,  80),
(17, 1, 'Shelly Dimmer 2',         'shelly-dimmer-2',         'WiFi leading/trailing-edge dimmer for LED and incandescent.',      19.90,  65),
(18, 1, 'Shelly Duo RGBW',         'shelly-duo-rgbw',         'E27 WiFi RGBW bulb, 9W, 800 lm, tunable white plus colour.',      14.90,  70),
(19, 1, 'Shelly Bulb Duo',         'shelly-bulb-duo',         'E27 WiFi CCT bulb, 9W, warm to cool white.',                       9.90,  75),
(20, 1, 'Shelly EM',               'shelly-em',               'WiFi energy meter for 2 circuits up to 120A each.',                29.90,  40),
(21, 1, 'Shelly 3EM',              'shelly-3em',              '3-phase WiFi energy meter, 63A per phase.',                        79.90,  20),
(22, 1, 'Shelly Button 1',         'shelly-button-1',         'Battery-powered WiFi scene-trigger button.',                        7.90,  90),
(23, 1, 'Shelly Door/Window 2',    'shelly-dw2',              'WiFi magnetic door and window open/close sensor.',                 11.90,  75),
(24, 1, 'Shelly Motion 2',         'shelly-motion-2',         'WiFi PIR motion sensor with lux and temperature.',                 19.90,  60),
(25, 1, 'Shelly Flood',            'shelly-flood',            'WiFi water-leak sensor with alarm buzzer.',                        14.90,  65),
(26, 1, 'Shelly Gas',              'shelly-gas',              'WiFi natural gas and LPG detector for kitchens.',                  39.90,  30),
(27, 1, 'Shelly TRV',              'shelly-trv',              'WiFi thermostatic radiator valve with schedule control.',          34.90,  50),
(28, 1, 'Shelly Plus 0-10V Dimmer','shelly-plus-0-10v',       'WiFi 0-10V signal dimmer for commercial LED drivers.',             24.90,  35),
(29, 1, 'Shelly Plus RGBW PM',     'shelly-plus-rgbw-pm',     'WiFi RGBW LED strip controller with power monitoring.',            24.90,  45),
(30, 1, 'Shelly Plus Uni',         'shelly-plus-uni',         'Universal WiFi I/O module with dry contacts and ADC input.',       17.90,  55),
(31, 1, 'Shelly Pro Dimmer 1PM',   'shelly-pro-dimmer-1pm',   'DIN-rail WiFi dimmer, 1-channel, 400W, power monitoring.',         39.90,  30),
(32, 1, 'Shelly Pro Dimmer 2PM',   'shelly-pro-dimmer-2pm',   'DIN-rail WiFi dimmer, dual-channel 200W each, power monitoring.',  54.90,  25),
(33, 1, 'Shelly BLU Button 1',     'shelly-blu-button1',      'Bluetooth Low Energy scene button, 5-year battery life.',           9.90,  80),
(34, 1, 'Shelly BLU Door/Window',  'shelly-blu-dw',           'BLE magnetic contact sensor, tiny form factor, 2-year battery.',   9.90,  80),
(35, 1, 'Shelly BLU Motion',       'shelly-blu-motion',       'BLE PIR motion sensor with lux reading, 2-year battery.',          16.90,  65),
(36, 1, 'Shelly BLU H&T',          'shelly-blu-ht',           'BLE temperature and humidity sensor, 2-year battery.',             14.90,  70),
(37, 1, 'Shelly Plus PM Mini Gen3','shelly-plus-pm-mini-gen3','Smallest WiFi power meter, monitors any 240V circuit.',             8.90,  85),
(38, 1, 'Shelly Plus Add-on',      'shelly-plus-addon',       'Expansion module for DS18B20, DHT, NTC sensors on Plus devices.',   9.90,  60),
(39, 1, 'Shelly Pro 1PM',          'shelly-pro-1pm',          'DIN-rail WiFi relay 1-channel with energy metering.',               29.90, 40),
(40, 1, 'Shelly 1PM Gen3',         'shelly-1pm-gen3',         'WiFi + Matter relay with power metering, Gen3 chipset.',            13.90, 75),
(41, 1, 'Shelly Plus 2PM Gen3',    'shelly-plus-2pm-gen3',    'Dual WiFi + Matter relay with power metering, Gen3.',               21.90, 60),
(42, 1, 'Shelly Plus Wall Dimmer', 'shelly-plus-wall-dimmer', 'Flush-mount WiFi dimmer, works without a neutral wire.',            34.90, 40),
(43, 1, 'Shelly Plus Wall Switch 1','shelly-plus-wall-sw1',   'Flush-mount single WiFi smart switch with relay.',                  24.90, 50),
(44, 1, 'Shelly Plus Wall Switch 4','shelly-plus-wall-sw4',   'Flush-mount 4-scene WiFi switch panel.',                           44.90, 30),
(45, 1, 'Shelly Smart Control',    'shelly-smart-control',    'Touch-screen WiFi control panel for lights and scenes.',            79.90, 20),
(46, 1, 'Shelly Plus Plug US',     'shelly-plus-plug-us',     'US-standard WiFi smart plug with power monitoring.',                14.90, 30),
(47, 1, 'Shelly Vintage A60',      'shelly-vintage-a60',      'WiFi filament-style decorative LED bulb, E27, 4W.',                 12.90, 55),
(48, 1, 'Shelly RGBW2',            'shelly-rgbw2',            'WiFi RGBW LED controller for LED strips up to 288W.',               17.90, 50),
(49, 1, 'Shelly Pro EM-50',        'shelly-pro-em50',         'DIN-rail WiFi energy meter, 50A CT clamps, 2 circuits.',            79.90, 20),
(50, 1, 'Shelly Qubino Wave 1PM',  'shelly-qubino-wave-1pm',  'Z-Wave 700 relay with power monitoring, EU DIN or wall box.',       49.90, 25);

-- ── SonOff Products (id 51-100) ───────────────────────────────────────────────
INSERT INTO products (id, brand_id, name, slug, description, price, stock) VALUES
( 51, 2, 'SONOFF Basic R4',             'sonoff-basic-r4',          'Smallest WiFi relay for in-line load switching.',                        7.90,  100),
( 52, 2, 'SONOFF Mini R4',              'sonoff-mini-r4',           'Compact WiFi relay for standard wall boxes, 10A.',                      10.90,   90),
( 53, 2, 'SONOFF Mini R4M',             'sonoff-mini-r4m',          'Matter-compatible mini relay, works with Apple/Google/Amazon.',          13.90,   70),
( 54, 2, 'SONOFF DUAL R3',              'sonoff-dual-r3',           'Dual-channel WiFi relay with individual power metering.',                16.90,   65),
( 55, 2, 'SONOFF POW R3 25A',           'sonoff-pow-r3-25a',        'High-current 25A WiFi relay with energy monitoring.',                   22.90,   50),
( 56, 2, 'SONOFF POW Elite 20A',        'sonoff-pow-elite-20a',     'WiFi energy monitor relay, 20A, display, 6 scheduling modes.',          29.90,   45),
( 57, 2, 'SONOFF TX Ultimate T3-3C',    'sonoff-tx-t3-3c',          '3-gang backlit glass touch switch, WiFi, scene buttons.',               24.90,   55),
( 58, 2, 'SONOFF M5-3C Matter',         'sonoff-m5-3c-matter',      'Matter 3-gang wall switch, works locally without cloud.',               18.90,   60),
( 59, 2, 'SONOFF D1 Dimmer',            'sonoff-d1',                'WiFi smart dimmer for dimmable LEDs and incandescent bulbs.',            14.90,   70),
( 60, 2, 'SONOFF ZBMINI L2',            'sonoff-zbmini-l2',         'Zigbee mini relay, neutral wire required, 10A.',                        11.90,   85),
( 61, 2, 'SONOFF ZBMINIL2 Extreme',     'sonoff-zbminil2-extreme',  'Zigbee relay, no neutral wire needed, fits 38mm wall box.',             13.90,   75),
( 62, 2, 'SONOFF ZBMini',               'sonoff-zbmini',            'Compact Zigbee relay module, 10A, requires neutral.',                    9.90,   90),
( 63, 2, 'SONOFF Zigbee Bridge Pro',    'sonoff-zbbridge-pro',      'WiFi to Zigbee gateway, supports up to 128 sub-devices.',               19.90,   50),
( 64, 2, 'SONOFF NSPanel Pro',          'sonoff-nspanel-pro',       'Flush-mount Zigbee+WiFi control panel with 3.95" touch display.',       69.90,   25),
( 65, 2, 'SONOFF NSPanel',              'sonoff-nspanel',           'WiFi thermostat control panel, 3.5" display, dual relay.',              39.90,   35),
( 66, 2, 'SONOFF SNZB-01P',             'sonoff-snzb-01p',          'Zigbee wireless scene button, long-life CR2477 battery.',                9.90,   95),
( 67, 2, 'SONOFF SNZB-02D',             'sonoff-snzb-02d',          'Zigbee temperature and humidity sensor with LCD display.',              14.90,   80),
( 68, 2, 'SONOFF SNZB-03P',             'sonoff-snzb-03p',          'Zigbee PIR motion sensor with 110° detection angle.',                   12.90,   80),
( 69, 2, 'SONOFF SNZB-04P',             'sonoff-snzb-04p',          'Zigbee door and window magnetic contact sensor.',                        9.90,   90),
( 70, 2, 'SONOFF SNZB-05P',             'sonoff-snzb-05p',          'Zigbee water leak sensor, instant flood alert.',                        11.90,   75),
( 71, 2, 'SONOFF SNZB-06P',             'sonoff-snzb-06p',          'Zigbee mmWave presence sensor, detects stationary people.',             24.90,   50),
( 72, 2, 'SONOFF ZBMICRO',              'sonoff-zbmicro',           'Zigbee USB power adapter, smart control for any USB device.',           14.90,   60),
( 73, 2, 'SONOFF Zigbee Dongle Plus-E', 'sonoff-dongle-plus-e',     'Zigbee 3.0 USB coordinator for Home Assistant and openHAB.',            19.90,   65),
( 74, 2, 'SONOFF SPM Main',             'sonoff-spm-main',          'WiFi smart power management hub for up to 4 SPM-4Relay modules.',       29.90,   30),
( 75, 2, 'SONOFF S26R2TPE Smart Plug',  'sonoff-s26r2tpe',          'Compact EU WiFi smart plug, 10A, works with Alexa and Google.',         11.90,   95),
( 76, 2, 'SONOFF S60TPE Smart Plug',    'sonoff-s60tpe',            'High-power EU WiFi plug, 20A, for kettles and heaters.',                17.90,   70),
( 77, 2, 'SONOFF POWR316',              'sonoff-powr316',           'WiFi power monitoring relay, 16A, DIN or wall mount.',                  18.90,   65),
( 78, 2, 'SONOFF POWR320D',             'sonoff-powr320d',          'WiFi power monitoring relay, 20A, with e-ink energy display.',          22.90,   55),
( 79, 2, 'SONOFF THR316D',              'sonoff-thr316d',           'WiFi temperature-triggered relay 16A, for heaters and coolers.',         14.90,  70),
( 80, 2, 'SONOFF THR320D',              'sonoff-thr320d',           'WiFi temperature relay 20A with RJ9 sensor connector.',                 17.90,   55),
( 81, 2, 'SONOFF iFan04-H',             'sonoff-ifan04-h',          'WiFi ceiling fan and light controller, supports RF remote.',             19.90,  60),
( 82, 2, 'SONOFF TX Ultimate T3-2C',    'sonoff-tx-t3-2c',          '2-gang glass touch switch, haptic feedback, WiFi.',                     21.90,  55),
( 83, 2, 'SONOFF SwitchMan R5',         'sonoff-switchman-r5',      'Battery WiFi scene controller, 6 buttons, mounts anywhere.',            14.90,  75),
( 84, 2, 'SONOFF SwitchMan M5-1C',      'sonoff-switchman-m5-1c',   'Matte panel WiFi wall switch, 1-gang, neutral required.',               13.90,  70),
( 85, 2, 'SONOFF Micro USB Adapter',    'sonoff-micro',             'WiFi smart USB power adapter 5V/2A for lamps and fans.',                 5.90,  100),
( 86, 2, 'SONOFF L3-5M RGBIC Strip',    'sonoff-l3-5m',             'WiFi RGBIC addressable LED strip 5m, music sync.',                      24.90,   50),
( 87, 2, 'SONOFF L2-5M CCT Strip',      'sonoff-l2-5m',             'WiFi CCT LED strip 5m, tunable warm to cool white.',                    19.90,   55),
( 88, 2, 'SONOFF B05-BL-A60',           'sonoff-b05-a60',           'WiFi RGBCW E27 bulb, 8W, 800lm, 16M colours.',                          8.90,   90),
( 89, 2, 'SONOFF B02-BL-A60',           'sonoff-b02-a60',           'WiFi CCT E27 bulb, 9W, tunable white 2700-6500K.',                       7.90,  100),
( 90, 2, 'SONOFF B05-B-GU10',           'sonoff-b05-gu10',          'WiFi RGBCW GU10 spot bulb, 4.9W, works with 50mm downlights.',           9.90,   80),
( 91, 2, 'SONOFF Cam Slim',             'sonoff-cam-slim',          'Indoor WiFi security camera, 1080p, AI motion detection.',              24.90,   45),
( 92, 2, 'SONOFF 4CHPROR3',             'sonoff-4chpror3',          'WiFi 4-channel pro relay, interlock and self-locking modes.',            34.90,   35),
( 93, 2, 'SONOFF RF Bridge R2',         'sonoff-rf-bridge-r2',      'WiFi to 433MHz RF bridge converts RF remotes to smart devices.',         14.90,   60),
( 94, 2, 'SONOFF ZBBRIDGE-P',           'sonoff-zbbridge-p',        'Zigbee Pro gateway over WiFi, local API, 128 device slots.',             19.90,   55),
( 95, 2, 'SONOFF iHost Local Hub',      'sonoff-ihost',             'Local Zigbee + Matter hub, no cloud needed, 4GB storage.',              69.90,   20),
( 96, 2, 'SONOFF MINIR4 Matter',        'sonoff-minir4-matter',     'Matter mini relay, local control without internet.',                     13.90,   75),
( 97, 2, 'SONOFF DUALR3 Lite',          'sonoff-dualr3-lite',       'Dual WiFi relay, lighter version without power monitoring.',             13.90,   70),
( 98, 2, 'SONOFF SPM-4Relay',           'sonoff-spm-4relay',        'Smart 4-outlet power strip sub-unit with energy monitoring.',            39.90,   30),
( 99, 2, 'SONOFF Zigbee Door Sensor',   'sonoff-zb-door',           'Slim Zigbee magnetic door sensor, fits narrow frames.',                  8.90,   90),
(100, 2, 'SONOFF B02-F-ST64',           'sonoff-b02-st64',          'WiFi vintage-style filament ST64 bulb, E27, 7W, dimmable.',              9.90,   70);

-- ── Tuya Products (id 101-150) ────────────────────────────────────────────────
INSERT INTO products (id, brand_id, name, slug, description, price, stock) VALUES
(101, 3, 'Tuya Smart Plug 16A EU',          'tuya-plug-16a-eu',         'WiFi smart plug 16A with energy monitoring, works with Tuya app.',      9.90,  100),
(102, 3, 'Tuya Zigbee Smart Plug 16A',      'tuya-zb-plug-16a',         'Zigbee 16A smart plug with energy metering, hub required.',            11.90,   85),
(103, 3, 'Tuya Smart Bulb E27 RGBCW 10W',  'tuya-bulb-e27-rgbcw',      'WiFi E27 RGBCW bulb, 10W, 16M colours, music sync.',                    8.90,   90),
(104, 3, 'Tuya Zigbee E27 Bulb RGBCW 9W',  'tuya-zb-bulb-e27',         'Zigbee E27 RGBCW bulb, 9W, instant response, no cloud.',               10.90,   80),
(105, 3, 'Tuya Smart Dimmer Switch',        'tuya-dimmer-sw',           'WiFi in-wall dimmer switch for LED, 1-way, 150W.',                      14.90,   70),
(106, 3, 'Tuya Zigbee Dimmer Module 2CH',   'tuya-zb-dimmer-2ch',       'Zigbee dual-channel dimmer module, fits inside wall boxes.',            16.90,   60),
(107, 3, 'Tuya Smart Curtain Motor',        'tuya-curtain-motor',       'WiFi tubular curtain motor, 45Nm torque, timer and scene support.',     39.90,   30),
(108, 3, 'Tuya Zigbee Curtain Module',      'tuya-zb-curtain-module',   'Zigbee curtain controller module for AC tubular motors.',              34.90,   30),
(109, 3, 'Tuya Zigbee PIR Motion Sensor',   'tuya-zb-pir',              'Zigbee PIR sensor, 7m range, battery-powered, pet-immune.',            12.90,   80),
(110, 3, 'Tuya Zigbee Temp+Humidity',       'tuya-zb-th',               'Zigbee temperature and humidity sensor with data history.',             9.90,   85),
(111, 3, 'Tuya Zigbee Door/Window Sensor',  'tuya-zb-door',             'Zigbee contact sensor, ultra-slim, 2-year battery life.',               7.90,   90),
(112, 3, 'Tuya Zigbee Water Leak Detector', 'tuya-zb-water',            'Zigbee water sensor with 85dB buzzer, immediate flood alert.',          11.90,   75),
(113, 3, 'Tuya Zigbee Smoke Detector',      'tuya-zb-smoke',            'Zigbee photoelectric smoke detector, EN 14604 compliant.',              19.90,   55),
(114, 3, 'Tuya Smart IR Blaster',           'tuya-ir-blaster',          'WiFi universal IR blaster, controls TVs, ACs and AV equipment.',        14.90,   70),
(115, 3, 'Tuya Zigbee Gateway Hub',         'tuya-zb-hub',              'WiFi + Zigbee 3.0 gateway, manages up to 128 sub-devices.',             24.90,   45),
(116, 3, 'Tuya Smart Thermostat TRV',       'tuya-trv-wifi',            'WiFi thermostatic radiator valve, weekly schedule, geofencing.',        27.90,   50),
(117, 3, 'Tuya Zigbee Thermostat TRV',      'tuya-zb-trv',              'Zigbee TRV with local boost mode, integrates with HA.',                 29.90,   45),
(118, 3, 'Tuya Smart Switch 2-gang',        'tuya-sw-2gang',            'WiFi 2-gang touch wall switch, neutral required.',                      13.90,   75),
(119, 3, 'Tuya Smart Switch 3-gang',        'tuya-sw-3gang',            'WiFi 3-gang touch wall switch with timer and countdown.',               16.90,   65),
(120, 3, 'Tuya Zigbee Switch Module 1CH',   'tuya-zb-sw-1ch',           'Zigbee single-channel relay module, in-wall, 10A.',                     12.90,   80),
(121, 3, 'Tuya Matter Smart Plug EU',       'tuya-matter-plug',         'Matter EU smart plug, local-first, Apple Home + Google compatible.',    16.90,   55),
(122, 3, 'Tuya Matter E27 Bulb RGBCW',     'tuya-matter-bulb-e27',     'Matter E27 RGBCW bulb, 9W, local control, no hub required.',            13.90,   60),
(123, 3, 'Tuya Smart Fan Speed Controller', 'tuya-fan-ctrl',            'WiFi fan speed controller, 4 speeds, compatible with ceiling fans.',    19.90,   50),
(124, 3, 'Tuya Zigbee Vibration Sensor',    'tuya-zb-vibration',        'Zigbee vibration and tilt sensor for mailboxes and windows.',           12.90,   65),
(125, 3, 'Tuya Smart CO2 + AQ Sensor',      'tuya-co2-aq',              'WiFi CO2, VOC, temperature and humidity air quality monitor.',           34.90,   40),
(126, 3, 'Tuya Zigbee Scene Switch 4-btn',  'tuya-zb-scene-sw4',        'Zigbee 4-button wireless scene switch, coin cell battery.',             14.90,   70),
(127, 3, 'Tuya Smart 3-Phase Energy Monitor','tuya-3ph-energy',         'WiFi 3-phase 80A energy monitor with CT clamps.',                       44.90,   25),
(128, 3, 'Tuya Zigbee Rotary Dimmer',       'tuya-zb-rotary-dimmer',    'Zigbee rotary knob dimmer switch, neutral-free design.',                18.90,   55),
(129, 3, 'Tuya Smart Outdoor Plug IP44',    'tuya-outdoor-plug',        'WiFi outdoor smart plug, IP44 weatherproof, 16A.',                      16.90,   55),
(130, 3, 'Tuya Zigbee Relay Module 2CH',    'tuya-zb-relay-2ch',        'Zigbee dual-channel relay module for lighting and appliances.',          13.90,   70),
(131, 3, 'Tuya Matter Bridge Pro',          'tuya-matter-bridge',       'WiFi+Zigbee+Matter bridge, unifies ecosystems locally.',                49.90,   20),
(132, 3, 'Tuya Smart RGBIC LED Strip 5m',  'tuya-rgbic-strip',         'WiFi RGBIC addressable LED strip 5m, music rhythm mode.',               19.90,   60),
(133, 3, 'Tuya Zigbee Soil Sensor',         'tuya-zb-soil',             'Zigbee soil moisture, temperature and conductivity sensor.',             14.90,   50),
(134, 3, 'Tuya Zigbee mmWave Presence',     'tuya-zb-mmwave',           'Zigbee 24GHz mmWave radar, detects stationary occupants.',              34.90,   35),
(135, 3, 'Tuya Zigbee Siren Alarm',         'tuya-zb-siren',            'Zigbee indoor siren, 90dB, colour LED flash, battery backup.',          16.90,   55),
(136, 3, 'Tuya Smart Power Strip 4-outlet', 'tuya-power-strip',         'WiFi 4-outlet smart strip, individual control, USB ports.',             22.90,   50),
(137, 3, 'Tuya Smart GU10 Spot RGBCW',     'tuya-spot-gu10',           'WiFi GU10 RGBCW spotlight, 4.5W, fits standard downlights.',             8.90,   80),
(138, 3, 'Tuya Zigbee GU10 Spot RGBCW',    'tuya-zb-spot-gu10',        'Zigbee GU10 RGBCW spot, instant local response.',                       10.90,   70),
(139, 3, 'Tuya Touch Panel Switch 3CH',     'tuya-touch-panel-3ch',     'WiFi glass 3-channel panel switch with backlight.',                      24.90,  45),
(140, 3, 'Tuya Matter Socket EU 20A',       'tuya-matter-socket-20a',   'Matter 20A socket, for high-load appliances, local control.',            17.90,  40),
(141, 3, 'Tuya Zigbee Air Quality Monitor', 'tuya-zb-air-quality',      'Zigbee PM2.5, CO2, temp, humidity all-in-one sensor.',                   39.90, 30),
(142, 3, 'Tuya Smart Flood Light 30W RGB',  'tuya-rgb-flood-30w',       'WiFi outdoor RGBCW flood light, 30W, IP65, timer and app.',              29.90, 35),
(143, 3, 'Tuya Zigbee Occupancy Sensor',    'tuya-zb-occupancy',        'Zigbee passive infrared occupancy sensor, 360° ceiling mount.',          22.90, 50),
(144, 3, 'Tuya Fingerbot Button Pusher',    'tuya-fingerbot',           'Bluetooth robotic finger, automates physical buttons and switches.',     19.90, 45),
(145, 3, 'Tuya Smart Lock Module',          'tuya-lock-module',         'WiFi + Zigbee lock module, integrates into existing mortise locks.',     29.90, 25),
(146, 3, 'Tuya Zigbee CO Detector',         'tuya-zb-co',               'Zigbee carbon monoxide detector, EN 50291 certified.',                   24.90, 45),
(147, 3, 'Tuya Multi-mode Gateway Pro',     'tuya-mm-gateway-pro',      'WiFi + Zigbee + Bluetooth 5.0 gateway hub, local API support.',          44.90, 25),
(148, 3, 'Tuya Smart Scene Switch 1-button','tuya-scene-sw1',           'WiFi single scene button, adhesive or screw mount.',                      9.90, 80),
(149, 3, 'Tuya Zigbee E14 Bulb RGBCW 5W',  'tuya-zb-bulb-e14',         'Zigbee E14 candle RGBCW bulb, 5W, fits chandeliers.',                    9.90, 70),
(150, 3, 'Tuya Smart Sprinkler Timer',      'tuya-sprinkler',           'WiFi irrigation timer, 8 zones, rain delay, voice control.',             24.90, 35);

-- ── Product capabilities ───────────────────────────────────────────────────────
-- Shelly WiFi products (all except BLU series and Qubino Wave)
INSERT INTO product_capabilities (product_id, capability_id) VALUES
( 1,1),( 2,1),( 3,1),( 4,1),( 5,1),( 6,1),( 7,1),( 8,1),( 9,1),(10,1),
(11,1),(12,1),(13,1),(14,1),(15,1),(16,1),(17,1),(18,1),(19,1),(20,1),
(21,1),(22,1),(23,1),(24,1),(25,1),(26,1),(27,1),(28,1),(29,1),(30,1),
(31,1),(32,1),(37,1),(38,1),(39,1),(40,1),(41,1),(42,1),(43,1),(44,1),
(45,1),(46,1),(47,1),(48,1),(49,1);
-- Shelly Matter (Gen3 devices)
INSERT INTO product_capabilities (product_id, capability_id) VALUES (40,3),(41,3);
-- Shelly Bluetooth (BLU series)
INSERT INTO product_capabilities (product_id, capability_id) VALUES (33,5),(34,5),(35,5),(36,5);
-- Shelly Z-Wave (Qubino Wave)
INSERT INTO product_capabilities (product_id, capability_id) VALUES (50,4);

-- SonOff WiFi products
INSERT INTO product_capabilities (product_id, capability_id) VALUES
(51,1),(52,1),(53,1),(54,1),(55,1),(56,1),(57,1),(58,1),(59,1),
(63,1),(64,1),(65,1),(74,1),(75,1),(76,1),(77,1),(78,1),(79,1),(80,1),
(81,1),(82,1),(83,1),(84,1),(85,1),(86,1),(87,1),(88,1),(89,1),(90,1),
(91,1),(92,1),(93,1),(94,1),(95,1),(97,1),(98,1),(100,1);
-- SonOff Matter
INSERT INTO product_capabilities (product_id, capability_id) VALUES (53,3),(58,3),(95,3),(96,3);
-- SonOff Zigbee
INSERT INTO product_capabilities (product_id, capability_id) VALUES
(60,2),(61,2),(62,2),(63,2),(64,2),(66,2),(67,2),(68,2),(69,2),(70,2),
(71,2),(72,2),(73,2),(94,2),(95,2),(99,2);

-- Tuya WiFi products
INSERT INTO product_capabilities (product_id, capability_id) VALUES
(101,1),(103,1),(105,1),(107,1),(114,1),(115,1),(116,1),(118,1),(119,1),
(123,1),(125,1),(127,1),(129,1),(131,1),(132,1),(136,1),(137,1),(139,1),
(140,1),(142,1),(145,1),(147,1),(148,1),(150,1);
-- Tuya Zigbee products
INSERT INTO product_capabilities (product_id, capability_id) VALUES
(102,2),(104,2),(106,2),(108,2),(109,2),(110,2),(111,2),(112,2),(113,2),
(115,2),(117,2),(120,2),(124,2),(126,2),(128,2),(130,2),(131,2),(133,2),
(134,2),(135,2),(138,2),(141,2),(143,2),(145,2),(146,2),(147,2),(149,2);
-- Tuya Matter products
INSERT INTO product_capabilities (product_id, capability_id) VALUES
(121,3),(122,3),(131,3),(140,3);
-- Tuya Bluetooth products
INSERT INTO product_capabilities (product_id, capability_id) VALUES (144,5),(147,5);
-- All Tuya brand products carry Tuya protocol capability (id=6)
INSERT INTO product_capabilities (product_id, capability_id) VALUES
(101,6),(102,6),(103,6),(104,6),(105,6),(106,6),(107,6),(108,6),(109,6),(110,6),
(111,6),(112,6),(113,6),(114,6),(115,6),(116,6),(117,6),(118,6),(119,6),(120,6),
(121,6),(122,6),(123,6),(124,6),(125,6),(126,6),(127,6),(128,6),(129,6),(130,6),
(131,6),(132,6),(133,6),(134,6),(135,6),(136,6),(137,6),(138,6),(139,6),(140,6),
(141,6),(142,6),(143,6),(144,6),(145,6),(146,6),(147,6),(148,6),(149,6),(150,6);

-- ── Demo Users ────────────────────────────────────────────────────────────────
-- Passwords stored as $SETUP$<plain> – auth.php upgrades to bcrypt on first login.
-- All demo accounts use password: demo123
INSERT INTO users (id, username, password_hash, email, role, full_name) VALUES
( 1, 'admin',   '$SETUP$demo123', 'admin@bpa.demo',   'admin', 'BPA Administrator'),
( 2, 'trouble', '$SETUP$demo123', 'trouble@bpa.demo', 'user',  'Terry Trouble'),
( 3, 'empty',   '$SETUP$demo123', 'empty@bpa.demo',   'user',  'Emma Empty'),
( 4, 'alice',   '$SETUP$demo123', 'alice@bpa.demo',   'user',  'Alice Andersen'),
( 5, 'bob',     '$SETUP$demo123', 'bob@bpa.demo',     'user',  'Bob Bergmann'),
( 6, 'charlie', '$SETUP$demo123', 'charlie@bpa.demo', 'user',  'Charlie Costa'),
( 7, 'diana',   '$SETUP$demo123', 'diana@bpa.demo',   'user',  'Diana Dubois'),
( 8, 'eve',     '$SETUP$demo123', 'eve@bpa.demo',     'user',  'Eve Eriksson'),
( 9, 'frank',   '$SETUP$demo123', 'frank@bpa.demo',   'user',  'Frank Fischer'),
(10, 'grace',   '$SETUP$demo123', 'grace@bpa.demo',   'user',  'Grace García'),
(11, 'henry',   '$SETUP$demo123', 'henry@bpa.demo',   'user',  'Henry Hansen'),
(12, 'iris',    '$SETUP$demo123', 'iris@bpa.demo',    'user',  'Iris Ivanova'),
(13, 'jack',    '$SETUP$demo123', 'jack@bpa.demo',    'user',  'Jack Johnson');

-- ── Pre-assigned use cases ────────────────────────────────────────────────────
INSERT INTO user_usecases (user_id, usecase_name, assigned_by) VALUES
(2, 'trouble',      1),
(3, 'empty_basket', 1);
