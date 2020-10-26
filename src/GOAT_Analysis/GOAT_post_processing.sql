------------------------------------------------------------------------------------------------------
------------------------------- GOAT Post-Processing tasks for BOGOTA --------------------------------
------------------------------------------------------------------------------------------------------

------------------------- Clean TAZ geometries (errors found in source file)  ------------------------

DROP TABLE IF EXISTS taz_polygon;
SELECT gid, area, muncod, nommun, zat, utam, ST_MakeValid(ST_Force2D((ST_Dump(geom)).geom::geometry)) AS geom INTO taz_polygon FROM taz;

--------------------------- Intersect and dissagregate TAZ using hexagons  --------------------------
--- See report, chapter 8
DROP TABLE IF EXISTS dissagregated_units;

SELECT a.gid, a.zat, b.grid_id, ST_MakeValid(ST_Intersection(b.geom,a.geom)) AS dissagregated_units 
INTO dissagregated_units 
FROM taz a, grid_heatmap b WHERE NOT st_isempty(ST_Intersection(b.geom,a.geom));

ALTER TABLE dissagregated_units ADD COLUMN area NUMERIC;

UPDATE dissagregated_units 
SET area = ST_AREA((dissagregated_units::geography));

DROP TABLE IF EXISTS dissagregated_units_areas;
WITH total_area_taz AS (SELECT gid, sum(area) AS total_area FROM dissagregated_units GROUP BY gid)
SELECT d.gid, d.zat, d.grid_id, d.dissagregated_units, ta.total_area, d.area/ta.total_area AS proportion_area 
INTO dissagregated_units_areas 
FROM dissagregated_units d, total_area_taz ta WHERE d.gid = ta.gid;

-------------------------------- Calculate accessibilities per hexagon -------------------------------
DROP TABLE IF EXISTS bog_accessibility_scores;
CREATE TABLE bog_accessibility_scores (grid_id NUMERIC, kindergarten NUMERIC, school NUMERIC, university NUMERIC, shopping NUMERIC, leisure NUMERIC, transmilenio NUMERIC, sitp NUMERIC, services NUMERIC, geom geometry);
INSERT INTO bog_accessibility_scores(
WITH kindergartens AS (
SELECT h.grid_id, h.accessibility_index AS kindergarten, g.geom
FROM heatmap_dynamic('{"kindergarten":{"sensitivity":800000,"weight":1}}'::jsonb,2,7533184,1) h, grid_heatmap g
WHERE h.grid_id = g.grid_id),
schools as(
SELECT h.grid_id, h.accessibility_index AS school
FROM heatmap_dynamic('{"school":{"sensitivity":950000,"weight":1}}'::jsonb,2,7533184,1) h, grid_heatmap g
WHERE h.grid_id = g.grid_id),
universities AS (
SELECT h.grid_id, h.accessibility_index AS university, g.geom
FROM heatmap_dynamic('{"university":{"sensitivity":1000000,"weight":1}}'::jsonb,2,7533184,1) h, grid_heatmap g
WHERE h.grid_id = g.grid_id
),
shopping  AS (
SELECT h.grid_id, h.accessibility_index AS shopping, g.geom
FROM heatmap_dynamic('{"bakery":{"sensitivity":750000,"weight":1},
					    "butcher":{"sensitivity":750000,"weight":1},
						"clothes":{"sensitivity":750000,"weight":1},
						"convenience":{"sensitivity":750000,"weight":1},
						"greengrocer":{"sensitivity":750000,"weight":1},
						"mall":{"sensitivity":750000,"weight":1},
						"shoes":{"sensitivity":750000,"weight":1},
						"supermarket":{"sensitivity":750000,"weight":1},
						"chemist":{"sensitivity":750000,"weight":1},
						"marketplace":{"sensitivity":750000,"weight":1}}'::jsonb,2,7533184,1) h, grid_heatmap g
WHERE h.grid_id = g.grid_id
),
leisure AS (
SELECT h.grid_id, h.accessibility_index AS leisure, g.geom
FROM heatmap_dynamic('{"cafe":{"sensitivity":900000,"weight":1},
					   "restaurant":{"sensitivity":900000,"weight":1},						
					   "cinema":{"sensitivity":900000,"weight":1},
					   "theater":{"sensitivity":900000,"weight":1},
					   "museum":{"sensitivity":900000,"weight":1},
					   "playground":{"sensitivity":900000,"weight":1},
					   "park":{"sensitivity":900000,"weight":1}}'::jsonb,2,7533184,1) h, grid_heatmap g
WHERE h.grid_id = g.grid_id
), transmilenio AS (
SELECT h.grid_id, h.accessibility_index AS transmilenio, g.geom
FROM heatmap_dynamic('{"transmilenio":{"sensitivity":550000,"weight":1},
					   "transmicable":{"sensitivity":550000,"weight":1}}'::jsonb,2,7533184,1) h, grid_heatmap g
WHERE h.grid_id = g.grid_id
),
sitp AS (
SELECT h.grid_id, h.accessibility_index AS sitp, g.geom
FROM heatmap_dynamic('{"sitp":{"sensitivity":350000,"weight":1}}'::jsonb,2,7533184,1) h, grid_heatmap g
WHERE h.grid_id = g.grid_id),
services AS (
SELECT h.grid_id, h.accessibility_index AS services, g.geom
FROM heatmap_dynamic('{"hairdresser":{"sensitivity":900000, "weight":1},
					   "bank":{"sensitivity":900000, "weight":1},
					   "dentist":{"sensitivity":900000,"weight":1},
					   "doctor":{"doctor":900000,"weight":1},
					   "pharmacy":{"pharmacy":900000,"weight":1},
					   "fuel":{"fuel":900000,"weight":1}}'::jsonb,2,7533184,1) h, grid_heatmap g
WHERE h.grid_id = g.grid_id
)
SELECT gh.grid_id, COALESCE(kindergarten,0), coalesce(school,0), coalesce(university,0), COALESCE(shopping,0), COALESCE(leisure,0), COALESCE(transmilenio,0), 
				   COALESCE(sitp,0), COALESCE(services,0), gh.geom FROM grid_heatmap gh
FULL JOIN schools s ON gh.grid_id = s.grid_id
FULL JOIN universities u ON gh.grid_id = u.grid_id
FULL JOIN shopping sh ON gh.grid_id = sh.grid_id
FULL JOIN leisure l ON gh.grid_id = l.grid_id
FULL JOIN transmilenio tm ON gh.grid_id = tm.grid_id
FULL JOIN sitp si ON gh.grid_id = si.grid_id
FULL JOIN kindergartens k ON gh.grid_id = k.grid_id
FULL JOIN services se ON gh.grid_id = se.grid_id);

--- Add total accessibility and group values (except TM and SITP)
ALTER TABLE bog_accessibility_scores ADD COLUMN total_accessibility NUMERIC;

UPDATE bog_accessibility_scores
SET total_accessibility = kindergarten + school + university + shopping + leisure + services;


SELECT * FROM bog_accessibility_scores;

-- Recalculate accessibilities in the smaller areas (check report, chapter 8)

DROP TABLE IF EXISTS heatmap_taz;
SELECT dua.gid, dua.zat, sum(kindergarten*proportion_area) AS kindergarten, sum(school*proportion_area) AS school, 
sum(university*proportion_area) AS university, sum(leisure*proportion_area) AS leisure, sum(shopping*proportion_area) AS shopping, sum(transmilenio*proportion_area) AS 
transmilenio, sum(sitp*proportion_area) AS sitp,  sum(services*proportion_area) AS services, sum(total_accessibility*proportion_area) AS reached_area, ST_Union(dissagregated_units) 
INTO heatmap_taz
FROM dissagregated_units_areas dua, bog_accessibility_scores bas
WHERE dua.grid_id = bas.grid_id GROUP BY dua.gid, dua.zat;
	

--------------------------------- Correct coordinates in the MHS trips -------------------------------	

ALTER TABLE bogota_trips_geodata ADD COLUMN IF NOT EXISTS geom geometry;
UPDATE bogota_trips_geodata 
SET "Latitud" = (CASE WHEN "Latitud" >=5 THEN "Latitud"/100000000000 ELSE "Latitud" END ),
"Longitud" = (CASE WHEN "Longitud" <=-100 THEN "Longitud"/10000000000 ELSE "Longitud" END );

UPDATE bogota_trips_geodata 
SET "Latitud" = (CASE WHEN "Latitud" <=1 THEN "Latitud"*10 ELSE "Latitud" END );

UPDATE bogota_trips_geodata
SET geom = ST_SetSRID(ST_MakePoint("Longitud"::float,"Latitud"::float), 4326);

----------------------------- Output 1: Vertical equity with Lorenz curves ---------------------------	
DROP TABLE IF EXISTS bog_accessibility_scores_pop;
CREATE TABLE bog_accessibility_scores_pop (LIKE bog_accessibility_scores INCLUDING ALL);
ALTER TABLE bog_accessibility_scores_pop ADD COLUMN population NUMERIC;

INSERT INTO bog_accessibility_scores_pop
SELECT bas.grid_id, kindergarten, school, university, shopping, leisure, transmilenio, sitp, services, bas.geom, bas.total_accessibility, gh.population 
FROM bog_accessibility_scores bas, grid_heatmap gh
WHERE bas.grid_id = gh.grid_id;

------ Output 2: Statistical descriptives per socio-economic strata group SES -- Vertical equity ------	
DROP TABLE IF EXISTS temporal_strata;
WITH strata_def AS (SELECT g.grid_id, p.main_strat, sum(p.population) AS pop_strata, row_number() 
OVER (PARTITION BY grid_id ORDER BY grid_id, sum(p.population) DESC )
FROM population p
JOIN grid_heatmap g
ON ST_Intersects(g.geom, p.geom)
GROUP BY p.gid, grid_id 
) SELECT * INTO temporal_strata FROM strata_def sd WHERE ROW_NUMBER = 1;

DROP TABLE IF EXISTS bog_accessibility_scores_pop_strata;
CREATE TABLE bog_accessibility_scores_pop_strata (grid_id NUMERIC, kindergarten NUMERIC, school NUMERIC, university NUMERIC, shopping NUMERIC, leisure NUMERIC, transmilenio NUMERIC, sitp NUMERIC, services NUMERIC,
geom geometry, total_accessibility NUMERIC, population NUMERIC, strata TEXT);

INSERT INTO bog_accessibility_scores_pop_strata
SELECT basp.*, ts.main_strat AS ses FROM bog_accessibility_scores_pop basp
LEFT JOIN temporal_strata ts
ON basp.grid_id = ts.grid_id;
--------------------------------------------- END EQUITY ----------------------------------------------	

-------------------------------------- TRAVEL BEHAVIOR ANALYSIS ---------------------------------------

--- Survey depuration
---- 1. Set geometry in households database (using survey coordinates)

ALTER TABLE bogota_mhs_households ADD COLUMN IF NOT EXISTS geom geometry;
UPDATE bogota_mhs_households
SET geom =  ST_SetSRID(ST_MakePoint("Longitud_fixed"::float,"Latitud_fixed"::float), 4326);

---- 2. Filter surveys in study area
DROP TABLE IF EXISTS bogota_households;
CREATE TABLE bogota_households (LIKE bogota_mhs_households INCLUDING ALL);

INSERT INTO bogota_households
SELECT bmh.* FROM bogota_mhs_households bmh
JOIN heatmap_taz ht ON ST_Intersects(bmh.geom, ht.st_union);

---- 3. Filter trips from surveys
DROP TABLE IF EXISTS bogota_trips;
CREATE TABLE bogota_trips (LIKE bogota_mhs_trips INCLUDING ALL);
INSERT INTO bogota_trips
SELECT bmt.* FROM bogota_households bh
LEFT JOIN bogota_mhs_trips bmt
ON bmt.id_hogar = bh."Id_Hogar";

--- Assign grouped trip purposes (the classification can be observed in the sources)
ALTER TABLE bogota_trips ADD COLUMN acc_purpose TEXT;
UPDATE bogota_trips
SET acc_purpose = (CASE WHEN "p17_Id_motivo_viaje" = 1 OR "p17_Id_motivo_viaje" = 2 OR "p17_Id_motivo_viaje" = 13 THEN 'work'
					    WHEN "p17_Id_motivo_viaje" = 3 THEN 'study'
					    WHEN "p17_Id_motivo_viaje"= 10 THEN 'shopping'
					    WHEN "p17_Id_motivo_viaje" = 5 OR "p17_Id_motivo_viaje" = 9 OR "p17_Id_motivo_viaje" = 12 OR "p17_Id_motivo_viaje" = 16 THEN 'leisure'
					    WHEN "p17_Id_motivo_viaje" = 4 OR "p17_Id_motivo_viaje" = 11 THEN 'service'
					    ELSE 'others' END); 
-- Detailed categories in study (persons occupation)

WITH occupation AS (
SELECT id_hogar, id_persona, p6_id_ocupacion, "p6_id_ocupacion_O1","p6_id_ocupacion_O2", "p6_id_ocupacion_O3" FROM bogota_mhs_persons)
UPDATE bogota_trips 
SET acc_purpose = (CASE WHEN acc_purpose = 'study' AND ("p6_id_ocupacion" = 35 OR "p6_id_ocupacion_O1" = 35 OR  "p6_id_ocupacion_O2" = 35 OR "p6_id_ocupacion_O3" = 35) THEN 'Kindergarten'
						WHEN acc_purpose = 'study' AND ("p6_id_ocupacion" = 1 OR "p6_id_ocupacion_O1" = 1) THEN 'school'
						WHEN acc_purpose = 'study' AND ("p6_id_ocupacion" <=4 AND "p6_id_ocupacion" >=2) OR ("p6_id_ocupacion_O1" <=4 AND "p6_id_ocupacion_O1" >=2) THEN 'university'
						ELSE acc_purpose END )
FROM occupation WHERE occupation.id_hogar = bogota_trips. id_hogar AND occupation.id_persona = bogota_trips.id_persona;
--- Groupe modes
ALTER TABLE bogota_trips ADD study_mode TEXT; 
UPDATE bogota_trips
SET study_mode = (CASE WHEN modo_principal = 'A pie' THEN 'walking'
                           WHEN modo_principal = ANY (ARRAY['Alimentador', 'Bicitaxi','Cable','Intermunicipal','SITP Provisional','SITP Zonal','TransMilenio','Transporte publico individual']) THEN 'PuT'
                           WHEN modo_principal = ANY (ARRAY['Auto','Moto']) THEN 'PrT'
                           WHEN modo_principal = ANY (ARRAY['Bicicleta','Bicitaxi']) THEN 'Cycling'
                           WHEN modo_principal = ANY (ARRAY['Otro','Patineta','Transporte Escolar','Transporte informal']) THEN 'Other'
                           ELSE modo_principal END);
                           
--- Calculate modal share per group
DROP TABLE IF EXISTS modal_share;
SELECT bt.acc_purpose, bt.study_mode, sum(f_exp) AS trips, count(f_exp) AS sample INTO modal_share FROM bogota_trips bt GROUP BY bt.acc_purpose, study_mode;

---------------------------------------- END SURVEY DEPURATION ----------------------------------------	
-------------------------------------- TRAVEL BEHAVIOR ANALYSIS ---------------------------------------

------------------------------------------ Indicators per ZAT -----------------------------------------
-- only homebased trips
DELETE FROM bogota_trips 
WHERE lugar_origen != 1;

--- 1. Walking share

DROP TABLE IF EXISTS walking_share;
WITH walking_trips AS (
SELECT * FROM bogota_trips WHERE study_mode = 'walking'),
walking_summary AS (
SELECT cc.zat, sum(bt.f_exp) AS f_exp_walking, count(study_mode) AS walking_trips FROM convalidation_codes cc, walking_trips bt WHERE "Id_Hogar" = id_hogar GROUP BY cc.zat ORDER BY cc.zat),
all_summary AS (
SELECT cc.zat, sum(bt.f_exp) AS f_exp_all, count(study_mode) AS all_trips FROM convalidation_codes cc, bogota_trips bt WHERE "Id_Hogar" = id_hogar GROUP BY cc.zat ORDER BY cc.zat)
SELECT wt.*, s.f_exp_all, s.all_trips, (wt.f_exp_walking/s.f_exp_all) AS walking_share_ef, (wt.walking_trips::numeric/s.all_trips::numeric) AS walking_share_n 
	INTO walking_share FROM walking_summary wt, all_summary s WHERE wt.zat = s.zat;

--- 2. Trips per person
DROP TABLE IF EXISTS walking_trips_person;
WITH walking_trips AS (
SELECT * FROM bogota_trips WHERE study_mode = 'walking'),
walking_summary AS (
SELECT cc.zat, sum(bt.f_exp) AS f_exp_walking, count(study_mode) AS walking_trips FROM convalidation_codes cc, walking_trips bt WHERE "Id_Hogar" = id_hogar GROUP BY cc.zat ORDER BY cc.zat),
persons_summary AS (
SELECT cc.zat, sum(bmp.f_exp) AS persons_ef, count(bmp.id_hogar) AS persons_n FROM bogota_mhs_persons bmp, convalidation_codes cc WHERE "Id_Hogar" = id_hogar GROUP BY cc.zat ORDER BY cc.zat)
SELECT ws.*,ps.persons_ef, ps.persons_n, (f_exp_walking/persons_ef) AS walking_trips_ef, (walking_trips::numeric/persons_n::numeric) AS walking_trips_n  
	INTO walking_trips_person
	FROM walking_summary ws, persons_summary ps WHERE ws.zat = ps.zat;

--- 3. Percentage of internal trips
DROP TABLE IF EXISTS inner_zone_trips;
WITH walking_trips AS (
SELECT * FROM bogota_trips WHERE study_mode = 'walking'),
self_zone AS (
SELECT cc.zat, sum(wt.f_exp) AS internal_ef, count(id_hogar) AS internal_n FROM walking_trips wt, convalidation_codes cc WHERE "Id_Hogar" = id_hogar AND zat_origen = zat_destino GROUP BY cc.zat),
all_trips AS (
SELECT cc.zat, sum(wt.f_exp) AS all_trips_ef, count(id_hogar) AS all_trips_n FROM walking_trips wt, convalidation_codes cc WHERE "Id_Hogar" = id_hogar AND zat_origen IS NOT NULL GROUP BY cc.zat
)
SELECT s.zat, internal_ef, internal_n, all_trips_ef, all_trips_n, (internal_ef/all_trips_ef) AS share_internal_trips_ef, (internal_n::numeric/all_trips_n::numeric) AS share_internal_trips_n 
	INTO inner_zone_trips
	FROM self_zone s, all_trips a WHERE s.zat = a.zat;

--- 4. No of different zats in destinations
DROP TABLE IF EXISTS amount_of_destinations;
WITH walking_trips AS (
SELECT * FROM bogota_trips WHERE study_mode = 'walking'),
destinations AS (
SELECT cc.zat, zat_destino, f_exp FROM  walking_trips wt, convalidation_codes cc WHERE "Id_Hogar" = id_hogar AND zat_destino IS NOT null
),
counter AS (
SELECT DISTINCT zat, zat_destino FROM destinations ORDER BY zat, zat_destino
)
SELECT zat, count(zat_destino) AS no_of_dest_zat INTO amount_of_destinations FROM counter GROUP BY zat;

--- 5. Walking trips for disabled persons
DROP TABLE IF EXISTS walking_trips_disabled;

WITH walking_trips AS (
SELECT id_hogar, id_persona, count(id_persona) AS trips_n, sum(f_exp) AS trips_ef FROM bogota_trips WHERE study_mode = 'walking' GROUP BY id_hogar, id_persona),
disabled_persons AS (
SELECT * FROM bogota_mhs_persons WHERE p8_id_dificultad_fisica_1 = 1 OR
									   p8_id_dificultad_fisica_2 = 1),
persons_with_trips AS (
SELECT dp.*, trips_n, trips_ef FROM disabled_persons dp
LEFT JOIN walking_trips wp ON dp.id_hogar = wp.id_hogar AND dp.id_persona = wp.id_persona
)
SELECT cc.zat, count(pwt.f_exp) AS persons_n, sum(pwt.f_exp) AS persons_ef, sum(trips_n) AS trips_n, sum(trips_ef) AS trips_ef, (sum(trips_ef)/sum(pwt.f_exp)) AS trips_person_ef, 
	(sum(trips_n)/count(pwt.f_exp)) AS trips_person_n 
	INTO walking_trips_disabled 
	FROM persons_with_trips pwt, convalidation_codes cc 
	WHERE pwt.id_hogar = "Id_Hogar" AND  cc.zat IS NOT NULL GROUP BY cc.zat;

--- 6. % Of driver's licences ownership
DROP TABLE IF EXISTS drivers_licenses;
WITH people_with_license AS (
SELECT * FROM bogota_mhs_persons WHERE p4_edad >=18 AND ("p10_licencia_conduccion_1" = 1 OR "p10_Licencia_conduccion_2" = 1 OR "p10_Licencia_conduccion_3" = 1)
),
all_major_people AS (
SELECT * FROM bogota_mhs_persons WHERE p4_edad >=18
), 
people_join AS (
SELECT amp.*, pwl.f_exp AS f_exp_license FROM all_major_people amp
LEFT JOIN people_with_license pwl ON amp.id_hogar = pwl.id_hogar)
SELECT cc.zat, sum(f_exp) AS all_ef, count(f_exp) AS all_n, sum(f_exp_license) AS license_ef, count(f_exp_license) AS license_n, (sum(f_exp_license)/sum(f_exp)) AS lic_pers_ef, (count(f_exp_license)::numeric/count(f_exp)::numeric) AS lic_pers_n
	INTO drivers_licenses
	FROM convalidation_codes cc, people_join pj 
	WHERE cc."Id_Hogar" = id_hogar GROUP BY cc.zat ORDER BY lic_pers_n desc;

--- 7. Vehicle ownership
DROP TABLE IF EXISTS vehicle_ownership;

WITH no_vehicles AS (
SELECT "Id_Hogar" AS id_hogar,p8_mayores_cinco_anios AS persons_above_5, (p1mc_automovil + p1mc_pickup + p1mc_motocicleta + p1mc_moto_carro + p1mc_triciclo_moto) AS all_vehicles, "Factor" FROM bogota_mhs_households
)
SELECT cc.zat, sum(all_vehicles) AS vehicles, sum(persons_above_5) AS persons, (sum(all_vehicles)/sum(persons_above_5)*1000) AS mot_rate 
	INTO vehicle_ownership 
	FROM no_vehicles nv, convalidation_codes cc 
	WHERE nv.id_hogar = "Id_Hogar" AND cc.zat IS NOT NULL GROUP BY cc.zat ORDER BY mot_rate desc;

--- 8. Average walking time
DROP TABLE IF EXISTS walking_time;
WITH walking_trips AS (
SELECT *, (p31_hora_llegada::numeric - hora_inicio_viaje::numeric) AS t_time FROM bogota_trips WHERE study_mode = 'walking' ),
walking_trips_filtered AS (
SELECT * FROM walking_trips WHERE t_time <= (1::NUMERIC /48::numeric) AND t_time >0 ORDER BY t_time
)
SELECT cc.zat, avg(t_time)*(24*60) AS t_time_min , count(t_time) AS sample 
	INTO walking_time	
	FROM walking_trips_filtered wtf, convalidation_codes cc 
	WHERE wtf.id_hogar = "Id_Hogar" GROUP BY cc.zat;

--- JOIN ALL INDICATORS WITH ACCESSIBILITY AND DELETE AUXILIARY TABLES
DROP TABLE IF EXISTS table_for_model;

WITH ind_1 AS (
SELECT ht.*, walking_share_ef, walking_share_n FROM heatmap_taz ht
LEFT JOIN walking_share ws ON ht.zat = ws.zat),
ind_2 AS (
SELECT ht.*, walking_trips_ef, walking_trips_n FROM ind_1 ht
LEFT JOIN walking_trips_person wtp ON ht.zat = wtp.zat),
ind_3 AS (
SELECT ht.*, share_internal_trips_ef, share_internal_trips_n FROM ind_2 ht
LEFT JOIN inner_zone_trips izt ON ht.zat = izt.zat ),
ind_4 AS (
SELECT ht.*, no_of_dest_zat FROM ind_3 ht
LEFT JOIN amount_of_destinations aod ON ht.zat = aod.zat),
ind_5 AS (
SELECT ht.*, trips_person_ef AS trips_person_disabled_ef, trips_person_n AS trips_person_disabled_n FROM ind_4 ht
LEFT JOIN walking_trips_disabled wtd ON ht.zat = wtd.zat),
ind_6 AS (
SELECT ht.*, lic_pers_ef, lic_pers_n FROM ind_5 ht
LEFT JOIN drivers_licenses dl ON ht.zat = dl.zat),
ind_7 AS (
SELECT ht.*, mot_rate FROM ind_6 ht
LEFT JOIN vehicle_ownership vo ON ht.zat = vo.zat)
SELECT ht.*, t_time_min, sample INTO table_for_model FROM ind_7 ht
LEFT JOIN walking_time wt ON ht.zat = wt.zat;

ALTER TABLE table_for_model ADD COLUMN geom geometry;
UPDATE table_for_model
SET geom = st_union;



------------------------------------------------------------------------------
----------------- Reclassification based on deciles of reached area-----------
------------------------------------------------------------------------------
----- Think about insert it into a function-----;

ALTER TABLE grid_heatmap DROP COLUMN area_deciles;
ALTER TABLE grid_heatmap DROP COLUMN numeric_deciles;

ALTER TABLE grid_heatmap ADD COLUMN IF NOT EXISTS area_deciles NUMERIC;
ALTER TABLE grid_heatmap ADD COLUMN IF NOT EXISTS numeric_deciles NUMERIC;

UPDATE grid_heatmap
SET area_deciles = (CASE WHEN area_isochrone IS NULL THEN 0 ELSE area_deciles END);
SELECT * FROM grid_heatmap;
--- New grouping based on area deciles

WITH 
decile05 AS (SELECT percentile_cont(0.05) WITHIN GROUP (ORDER BY area_isochrone ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap WHERE area_deciles IS null ) AS filtered),
decile10 AS (SELECT percentile_cont(0.1) WITHIN GROUP (ORDER BY area_isochrone ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap WHERE area_deciles IS null ) AS filtered),
decile15 AS (SELECT percentile_cont(0.15) WITHIN GROUP (ORDER BY area_isochrone ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap WHERE area_deciles IS null ) AS filtered),
decile20 AS (SELECT percentile_cont(0.20) WITHIN GROUP (ORDER BY area_isochrone ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap WHERE area_deciles IS null ) AS filtered),
decile25 AS (SELECT percentile_cont(0.25) WITHIN GROUP (ORDER BY area_isochrone ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap WHERE area_deciles IS null ) AS filtered),
decile30 AS (SELECT percentile_cont(0.30) WITHIN GROUP (ORDER BY area_isochrone ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap WHERE area_deciles IS null ) AS filtered),
decile35 AS (SELECT percentile_cont(0.35) WITHIN GROUP (ORDER BY area_isochrone ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap WHERE area_deciles IS null ) AS filtered),
decile40 AS (SELECT percentile_cont(0.40) WITHIN GROUP (ORDER BY area_isochrone ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap WHERE area_deciles IS null ) AS filtered),
decile45 AS (SELECT percentile_cont(0.45) WITHIN GROUP (ORDER BY area_isochrone ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap WHERE area_deciles IS null ) AS filtered),
decile55 AS (SELECT percentile_cont(0.55) WITHIN GROUP (ORDER BY area_isochrone ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap WHERE area_deciles IS null ) AS filtered),
decile50 AS (SELECT percentile_cont(0.50) WITHIN GROUP (ORDER BY area_isochrone ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap WHERE area_deciles IS null ) AS filtered),
decile60 AS (SELECT percentile_cont(0.60) WITHIN GROUP (ORDER BY area_isochrone ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap WHERE area_deciles IS null ) AS filtered),
decile65 AS (SELECT percentile_cont(0.65) WITHIN GROUP (ORDER BY area_isochrone ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap WHERE area_deciles IS null ) AS filtered),
decile70 AS (SELECT percentile_cont(0.70) WITHIN GROUP (ORDER BY area_isochrone ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap WHERE area_deciles IS null ) AS filtered),
decile75 AS (SELECT percentile_cont(0.75) WITHIN GROUP (ORDER BY area_isochrone ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap WHERE area_deciles IS null ) AS filtered),
decile80 AS (SELECT percentile_cont(0.80) WITHIN GROUP (ORDER BY area_isochrone ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap WHERE area_deciles IS null ) AS filtered),
decile85 AS (SELECT percentile_cont(0.85) WITHIN GROUP (ORDER BY area_isochrone ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap WHERE area_deciles IS null ) AS filtered),
decile90 AS (SELECT percentile_cont(0.90) WITHIN GROUP (ORDER BY area_isochrone ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap WHERE area_deciles IS null ) AS filtered),
decile95 AS (SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY area_isochrone ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap WHERE area_deciles IS null ) AS filtered),
decile100 AS (SELECT max(area_isochrone) FROM grid_heatmap AS filtered)
UPDATE grid_heatmap
SET area_deciles = (CASE WHEN area_isochrone <= (SELECT * FROM decile05) AND area_isochrone >=0 THEN 1
						 WHEN area_isochrone <= (SELECT * FROM decile10) AND area_isochrone >(SELECT * FROM decile05) THEN 2
						 WHEN area_isochrone <= (SELECT * FROM decile15) AND area_isochrone >(SELECT * FROM decile10) THEN 3
						 WHEN area_isochrone <= (SELECT * FROM decile20) AND area_isochrone >(SELECT * FROM decile15) THEN 4
						 WHEN area_isochrone <= (SELECT * FROM decile25) AND area_isochrone >(SELECT * FROM decile20) THEN 5
						 WHEN area_isochrone <= (SELECT * FROM decile30) AND area_isochrone >(SELECT * FROM decile25) THEN 6
						 WHEN area_isochrone <= (SELECT * FROM decile35) AND area_isochrone >(SELECT * FROM decile30) THEN 7
                         WHEN area_isochrone <= (SELECT * FROM decile40) AND area_isochrone >(SELECT * FROM decile35) THEN 8
                         WHEN area_isochrone <= (SELECT * FROM decile45) AND area_isochrone >(SELECT * FROM decile40) THEN 9
                         WHEN area_isochrone <= (SELECT * FROM decile50) AND area_isochrone >(SELECT * FROM decile45) THEN 10
                         WHEN area_isochrone <= (SELECT * FROM decile55) AND area_isochrone >(SELECT * FROM decile50) THEN 11
                         WHEN area_isochrone <= (SELECT * FROM decile60) AND area_isochrone >(SELECT * FROM decile55) THEN 12
                         WHEN area_isochrone <= (SELECT * FROM decile65) AND area_isochrone >(SELECT * FROM decile60) THEN 13
                         WHEN area_isochrone <= (SELECT * FROM decile70) AND area_isochrone >(SELECT * FROM decile65) THEN 14
                         WHEN area_isochrone <= (SELECT * FROM decile75) AND area_isochrone >(SELECT * FROM decile70) THEN 15
                         WHEN area_isochrone <= (SELECT * FROM decile80) AND area_isochrone >(SELECT * FROM decile75) THEN 16
                         WHEN area_isochrone <= (SELECT * FROM decile85) AND area_isochrone >(SELECT * FROM decile80) THEN 17
                         WHEN area_isochrone <= (SELECT * FROM decile90) AND area_isochrone >(SELECT * FROM decile85) THEN 18
                         WHEN area_isochrone <= (SELECT * FROM decile95) AND area_isochrone >(SELECT * FROM decile90) THEN 19
                         WHEN area_isochrone IS NULL THEN 0
                         ELSE 20 END);
                        
WITH averages AS(
SELECT area_deciles, min(area_isochrone) AS minimum,  max(area_isochrone) AS maximum, (min(area_isochrone)+max(area_isochrone))/2 AS average FROM grid_heatmap GROUP BY area_deciles
)
UPDATE grid_heatmap 
SET numeric_deciles = (CASE WHEN area_deciles = 0 THEN 0
						    WHEN area_deciles = 1 THEN (SELECT average FROM averages WHERE area_deciles = 1)
						    WHEN area_deciles = 2 THEN (SELECT average FROM averages WHERE area_deciles = 2)
						    WHEN area_deciles = 3 THEN (SELECT average FROM averages WHERE area_deciles = 3)
						    WHEN area_deciles = 4 THEN (SELECT average FROM averages WHERE area_deciles = 4)
						    WHEN area_deciles = 5 THEN (SELECT average FROM averages WHERE area_deciles = 5)
						    WHEN area_deciles = 6 THEN (SELECT average FROM averages WHERE area_deciles = 6)
						    WHEN area_deciles = 7 THEN (SELECT average FROM averages WHERE area_deciles = 7)
						    WHEN area_deciles = 8 THEN (SELECT average FROM averages WHERE area_deciles = 8)
						    WHEN area_deciles = 9 THEN (SELECT average FROM averages WHERE area_deciles = 9)
						    WHEN area_deciles = 10 THEN (SELECT average FROM averages WHERE area_deciles = 10)
						    WHEN area_deciles = 11 THEN (SELECT average FROM averages WHERE area_deciles = 11)
						    WHEN area_deciles = 12 THEN (SELECT average FROM averages WHERE area_deciles = 12)
						    WHEN area_deciles = 13 THEN (SELECT average FROM averages WHERE area_deciles = 13)
						    WHEN area_deciles = 14 THEN (SELECT average FROM averages WHERE area_deciles = 14)
						    WHEN area_deciles = 15 THEN (SELECT average FROM averages WHERE area_deciles = 15)
						    WHEN area_deciles = 16 THEN (SELECT average FROM averages WHERE area_deciles = 16)
						    WHEN area_deciles = 17 THEN (SELECT average FROM averages WHERE area_deciles = 17)
						    WHEN area_deciles = 18 THEN (SELECT average FROM averages WHERE area_deciles = 18)
						    WHEN area_deciles = 19 THEN (SELECT average FROM averages WHERE area_deciles = 19)
						    WHEN area_deciles = 20 THEN (SELECT average FROM averages WHERE area_deciles = 20) END 
);

SELECT * FROM grid_heatmap;

-- Update convalidation codes

DROP TABLE IF EXISTS convalidation_codes_deciles;
SELECT cc.*, area_deciles AS deciles INTO convalidation_codes_deciles FROM convalidation_codes cc, grid_heatmap gh WHERE cc.grid_id = gh.grid_id;

SELECT * FROM convalidation_codes_deciles;
SELECT * FROM grid_heatmap;

--- Indicators per Decile group
--- 1. Walking share

DROP TABLE IF EXISTS walking_share_deciles;
WITH walking_trips AS (
SELECT * FROM bogota_trips WHERE study_mode = 'walking'),
walking_summary AS (
SELECT cc.deciles, sum(bt.f_exp) AS f_exp_walking, count(study_mode) AS walking_trips FROM convalidation_codes_deciles cc, walking_trips bt WHERE "Id_Hogar" = id_hogar GROUP BY cc.deciles ORDER BY cc.deciles),
all_summary AS (
SELECT cc.deciles, sum(bt.f_exp) AS f_exp_all, count(study_mode) AS all_trips FROM convalidation_codes_deciles cc, bogota_trips bt WHERE "Id_Hogar" = id_hogar GROUP BY cc.deciles ORDER BY cc.deciles)
SELECT wt.*, s.f_exp_all, s.all_trips, (wt.f_exp_walking/s.f_exp_all) AS walking_share_ef, (wt.walking_trips::numeric/s.all_trips::numeric) AS walking_share_n 
	INTO walking_share_deciles FROM walking_summary wt, all_summary s WHERE wt.deciles = s.deciles;

--SELECT * FROM walking_share_deciles;

--- 2. Trips per person
DROP TABLE IF EXISTS walking_trips_person_deciles;
WITH walking_trips AS (
SELECT * FROM bogota_trips WHERE study_mode = 'walking'),
walking_summary AS (
SELECT cc.deciles, sum(bt.f_exp) AS f_exp_walking, count(study_mode) AS walking_trips FROM convalidation_codes_deciles cc, walking_trips bt WHERE "Id_Hogar" = id_hogar GROUP BY cc.deciles ORDER BY cc.deciles),
persons_summary AS (
SELECT cc.deciles, sum(bmp.f_exp) AS persons_ef, count(bmp.id_hogar) AS persons_n FROM bogota_mhs_persons bmp, convalidation_codes_deciles cc WHERE "Id_Hogar" = id_hogar GROUP BY cc.deciles ORDER BY cc.deciles)
SELECT ws.*,ps.persons_ef, ps.persons_n, (f_exp_walking/persons_ef) AS walking_trips_ef, (walking_trips::numeric/persons_n::numeric) AS walking_trips_n  
	INTO walking_trips_person_deciles
	FROM walking_summary ws, persons_summary ps WHERE ws.deciles = ps.deciles;

--- 3. Percentage of internal trips
DROP TABLE IF EXISTS inner_zone_trips_deciles;
WITH walking_trips AS (
SELECT * FROM bogota_trips WHERE study_mode = 'walking'),
self_zone AS (
SELECT cc.deciles, sum(wt.f_exp) AS internal_ef, count(id_hogar) AS internal_n FROM walking_trips wt, convalidation_codes_deciles cc WHERE "Id_Hogar" = id_hogar AND zat_origen = zat_destino GROUP BY cc.deciles),
all_trips AS (
SELECT cc.deciles, sum(wt.f_exp) AS all_trips_ef, count(id_hogar) AS all_trips_n FROM walking_trips wt, convalidation_codes_deciles cc WHERE "Id_Hogar" = id_hogar AND zat_origen IS NOT NULL GROUP BY cc.deciles
)
SELECT s.deciles, internal_ef, internal_n, all_trips_ef, all_trips_n, (internal_ef/all_trips_ef) AS share_internal_trips_ef, (internal_n::numeric/all_trips_n::numeric) AS share_internal_trips_n 
	INTO inner_zone_trips_deciles
	FROM self_zone s, all_trips a WHERE s.deciles = a.deciles;

--- 4. No of different zats in destinations
DROP TABLE IF EXISTS amount_of_destinations_deciles;
WITH walking_trips AS (
SELECT * FROM bogota_trips WHERE study_mode = 'walking'),
destinations AS (
SELECT cc.zat, zat_destino, f_exp, cc.deciles FROM  walking_trips wt, convalidation_codes_deciles cc WHERE "Id_Hogar" = id_hogar AND zat_destino IS NOT null
),
counter AS (
SELECT DISTINCT deciles, zat, zat_destino FROM destinations ORDER BY zat, zat_destino
), sumup AS (
SELECT deciles, zat, count(zat_destino) AS no_of_dest_zat FROM counter GROUP BY zat, deciles)
SELECT deciles, avg(no_of_dest_zat) AS no_of_dest_zat INTO amount_of_destinations_deciles FROM sumup GROUP BY deciles;

--- 5. Walking trips for disabled persons
DROP TABLE IF EXISTS walking_trips_disabled_deciles;

WITH walking_trips AS (
SELECT id_hogar, id_persona, count(id_persona) AS trips_n, sum(f_exp) AS trips_ef FROM bogota_trips WHERE study_mode = 'walking' GROUP BY id_hogar, id_persona),
disabled_persons AS (
SELECT * FROM bogota_mhs_persons WHERE p8_id_dificultad_fisica_1 = 1 OR
									   p8_id_dificultad_fisica_2 = 1),
persons_with_trips AS (
SELECT dp.*, trips_n, trips_ef FROM disabled_persons dp
LEFT JOIN walking_trips wp ON dp.id_hogar = wp.id_hogar AND dp.id_persona = wp.id_persona
)
SELECT cc.deciles, count(pwt.f_exp) AS persons_n, sum(pwt.f_exp) AS persons_ef, sum(trips_n) AS trips_n, sum(trips_ef) AS trips_ef, (sum(trips_ef)/sum(pwt.f_exp)) AS trips_person_ef, 
	(sum(trips_n)/count(pwt.f_exp)) AS trips_person_n 
	INTO walking_trips_disabled_deciles
	FROM persons_with_trips pwt, convalidation_codes_deciles cc 
	WHERE pwt.id_hogar = "Id_Hogar" AND  cc.zat IS NOT NULL GROUP BY cc.deciles;

--- 6. % Of driver's licences ownership
DROP TABLE IF EXISTS drivers_licenses_deciles;
WITH people_with_license AS (
SELECT * FROM bogota_mhs_persons WHERE p4_edad >=18 AND ("p10_licencia_conduccion_1" = 1 OR "p10_Licencia_conduccion_2" = 1 OR "p10_Licencia_conduccion_3" = 1)
),
all_major_people AS (
SELECT * FROM bogota_mhs_persons WHERE p4_edad >=18
), 
people_join AS (
SELECT amp.*, pwl.f_exp AS f_exp_license FROM all_major_people amp
LEFT JOIN people_with_license pwl ON amp.id_hogar = pwl.id_hogar)
SELECT cc.deciles, sum(f_exp) AS all_ef, count(f_exp) AS all_n, sum(f_exp_license) AS license_ef, count(f_exp_license) AS license_n, (sum(f_exp_license)/sum(f_exp)) AS lic_pers_ef, (count(f_exp_license)::numeric/count(f_exp)::numeric) AS lic_pers_n
	INTO drivers_licenses_deciles
	FROM convalidation_codes_deciles cc, people_join pj 
	WHERE cc."Id_Hogar" = id_hogar GROUP BY cc.deciles ORDER BY lic_pers_n desc;

--- 7. Vehicle ownership
DROP TABLE IF EXISTS vehicle_ownership_deciles;

WITH no_vehicles AS (
SELECT "Id_Hogar" AS id_hogar,p8_mayores_cinco_anios AS persons_above_5, (p1mc_automovil + p1mc_pickup + p1mc_motocicleta + p1mc_moto_carro + p1mc_triciclo_moto) AS all_vehicles, "Factor" FROM bogota_mhs_households
)
SELECT cc.deciles, sum(all_vehicles) AS vehicles, sum(persons_above_5) AS persons, (sum(all_vehicles)/sum(persons_above_5)*1000) AS mot_rate 
	INTO vehicle_ownership_deciles 
	FROM no_vehicles nv, convalidation_codes_deciles cc 
	WHERE nv.id_hogar = "Id_Hogar" AND cc.zat IS NOT NULL GROUP BY cc.deciles ORDER BY mot_rate desc;
SELECT * FROM vehicle_ownership_deciles ORDER BY deciles;

--- 8. Average walking time
DROP TABLE IF EXISTS walking_time_deciles;
WITH walking_trips AS (
SELECT *, (p31_hora_llegada::numeric - hora_inicio_viaje::numeric) AS t_time FROM bogota_trips WHERE study_mode = 'walking' ),
walking_trips_filtered AS (
SELECT * FROM walking_trips WHERE t_time <= (1::NUMERIC /48::numeric) AND t_time >0 ORDER BY t_time
)
SELECT cc.deciles, avg(t_time)*(24*60) AS t_time_min , count(t_time) AS sample 
	INTO walking_time_deciles	
	FROM walking_trips_filtered wtf, convalidation_codes_deciles cc 
	WHERE wtf.id_hogar = "Id_Hogar" GROUP BY cc.deciles;
SELECT * FROM walking_time_deciles ORDER BY deciles;

--- Join
DROP TABLE IF EXISTS table_for_model_deciles;
WITH areas AS (
SELECT area_deciles ,numeric_deciles , ST_union(geom) AS geom FROM grid_heatmap GROUP BY area_deciles, numeric_deciles
),
ind_1 AS (
SELECT ht.*, walking_share_ef, walking_share_n FROM areas ht
LEFT JOIN walking_share_deciles ws ON ht.area_deciles = ws.deciles),
ind_2 AS (
SELECT ht.*, walking_trips_ef, walking_trips_n FROM ind_1 ht
LEFT JOIN walking_trips_person_deciles wtp ON ht.area_deciles = wtp.deciles),
ind_3 AS (
SELECT ht.*, share_internal_trips_ef, share_internal_trips_n FROM ind_2 ht
LEFT JOIN inner_zone_trips_deciles izt ON ht.area_deciles = izt.deciles ),
ind_4 AS (
SELECT ht.*, no_of_dest_zat FROM ind_3 ht
LEFT JOIN amount_of_destinations_deciles aod ON ht.area_deciles = aod.deciles),
ind_5 AS (
SELECT ht.*, trips_person_ef AS trips_person_disabled_ef, trips_person_n AS trips_person_disabled_n FROM ind_4 ht
LEFT JOIN walking_trips_disabled_deciles wtd ON ht.area_deciles = wtd.deciles),
ind_6 AS (
SELECT ht.*, lic_pers_ef, lic_pers_n FROM ind_5 ht
LEFT JOIN drivers_licenses_deciles dl ON ht.area_deciles = dl.deciles),
ind_7 AS (
SELECT ht.*, mot_rate FROM ind_6 ht
LEFT JOIN vehicle_ownership_deciles vo ON ht.area_deciles = vo.deciles)
SELECT ht.*, t_time_min, sample INTO table_for_model_deciles FROM ind_7 ht
LEFT JOIN walking_time_deciles wt ON ht.area_deciles = wt.deciles;

SELECT * FROM table_for_model_deciles;
SELECT * FROM vehicle_ownership_deciles vod;
DELETE FROM table_for_model_deciles
WHERE numeric_deciles = 0;
----------------------------------------------------------------------
--- Trial 3, group by total accessibility score
----------------------------------------------------------------------

SELECT * FROM bog_accessibility_scores_pop_strata; 
ALTER TABLE bog_accessibility_scores_pop_strata ADD COLUMN area_isochrones NUMERIC;


UPDATE bog_accessibility_scores_pop_strata 
SET total_accessibility = kindergarten + school + university + shopping + leisure + services;

--DROP TABLE IF EXISTS grid_heatmap_acc;
--CREATE TABLE grid_heatmap_acc (geom geometry, grid_id int4, area_isochrones float8, percentile_total_accessibility int2, population int4, percentile_population int2, area_deciles NUMERIC, numeric_deciles NUMERIC, total_accessibility NUMERIC, accessibility_deciles NUMERIC, accessibility_numeric_decil NUMERIC)

SELECT * FROM grid_heatmap;
--- Group grid_heatmap_accessiblilty

DROP TABLE IF EXISTS grid_heatmap_acc;
SELECT gh.*, total_accessibility INTO grid_heatmap_acc FROM grid_heatmap gh, bog_accessibility_scores_pop_strata basps WHERE gh.grid_id = basps.grid_id ORDER BY total_accessibility DESC ;


--- Calculate accessibility percentiles

SELECT * FROM grid_heatmap_acc ORDER BY total_accessibility;

ALTER TABLE grid_heatmap_acc ADD COLUMN accessibility_percentile NUMERIC;

UPDATE grid_heatmap_acc
SET accessibility_percentile = (CASE WHEN total_accessibility = 0 THEN 0 ELSE accessibility_percentile END);

--- New grouping based on area deciles

WITH 
decile05 AS (SELECT percentile_cont(0.05) WITHIN GROUP (ORDER BY total_accessibility ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap_acc WHERE accessibility_percentile IS NULL) AS filtered),
decile10 AS (SELECT percentile_cont(0.10) WITHIN GROUP (ORDER BY total_accessibility ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap_acc WHERE accessibility_percentile IS NULL) AS filtered),
decile15 AS (SELECT percentile_cont(0.15) WITHIN GROUP (ORDER BY total_accessibility ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap_acc WHERE accessibility_percentile IS NULL) AS filtered),
decile20 AS (SELECT percentile_cont(0.20) WITHIN GROUP (ORDER BY total_accessibility ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap_acc WHERE accessibility_percentile IS NULL) AS filtered),
decile25 AS (SELECT percentile_cont(0.25) WITHIN GROUP (ORDER BY total_accessibility ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap_acc WHERE accessibility_percentile IS NULL) AS filtered),
decile30 AS (SELECT percentile_cont(0.30) WITHIN GROUP (ORDER BY total_accessibility ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap_acc WHERE accessibility_percentile IS NULL) AS filtered),
decile35 AS (SELECT percentile_cont(0.35) WITHIN GROUP (ORDER BY total_accessibility ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap_acc WHERE accessibility_percentile IS NULL) AS filtered),
decile40 AS (SELECT percentile_cont(0.40) WITHIN GROUP (ORDER BY total_accessibility ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap_acc WHERE accessibility_percentile IS NULL) AS filtered),
decile45 AS (SELECT percentile_cont(0.45) WITHIN GROUP (ORDER BY total_accessibility ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap_acc WHERE accessibility_percentile IS NULL) AS filtered),
decile50 AS (SELECT percentile_cont(0.50) WITHIN GROUP (ORDER BY total_accessibility ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap_acc WHERE accessibility_percentile IS NULL) AS filtered),
decile55 AS (SELECT percentile_cont(0.55) WITHIN GROUP (ORDER BY total_accessibility ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap_acc WHERE accessibility_percentile IS NULL) AS filtered),
decile60 AS (SELECT percentile_cont(0.60) WITHIN GROUP (ORDER BY total_accessibility ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap_acc WHERE accessibility_percentile IS NULL) AS filtered),
decile65 AS (SELECT percentile_cont(0.65) WITHIN GROUP (ORDER BY total_accessibility ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap_acc WHERE accessibility_percentile IS NULL) AS filtered),
decile70 AS (SELECT percentile_cont(0.70) WITHIN GROUP (ORDER BY total_accessibility ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap_acc WHERE accessibility_percentile IS NULL) AS filtered),
decile75 AS (SELECT percentile_cont(0.75) WITHIN GROUP (ORDER BY total_accessibility ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap_acc WHERE accessibility_percentile IS NULL) AS filtered),
decile80 AS (SELECT percentile_cont(0.80) WITHIN GROUP (ORDER BY total_accessibility ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap_acc WHERE accessibility_percentile IS NULL) AS filtered),
decile85 AS (SELECT percentile_cont(0.85) WITHIN GROUP (ORDER BY total_accessibility ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap_acc WHERE accessibility_percentile IS NULL) AS filtered),
decile90 AS (SELECT percentile_cont(0.90) WITHIN GROUP (ORDER BY total_accessibility ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap_acc WHERE accessibility_percentile IS NULL) AS filtered),
decile95 AS (SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY total_accessibility ASC) AS decile_10 FROM (SELECT * FROM grid_heatmap_acc WHERE accessibility_percentile IS NULL) AS filtered),
decile100 AS (SELECT max(total_accessibility) FROM grid_heatmap_acc AS filtered)
UPDATE grid_heatmap_acc
SET accessibility_percentile = (CASE WHEN total_accessibility <= (SELECT * FROM decile05) AND total_accessibility >0 THEN 1
						 WHEN total_accessibility <= (SELECT * FROM decile10) AND total_accessibility >(SELECT * FROM decile05) THEN 2
						 WHEN total_accessibility <= (SELECT * FROM decile15) AND total_accessibility >(SELECT * FROM decile10) THEN 3
						 WHEN total_accessibility <= (SELECT * FROM decile20) AND total_accessibility >(SELECT * FROM decile15) THEN 4
						 WHEN total_accessibility <= (SELECT * FROM decile25) AND total_accessibility >(SELECT * FROM decile20) THEN 5
						 WHEN total_accessibility <= (SELECT * FROM decile30) AND total_accessibility >(SELECT * FROM decile25) THEN 6
						 WHEN total_accessibility <= (SELECT * FROM decile35) AND total_accessibility >(SELECT * FROM decile30) THEN 7
                         WHEN total_accessibility <= (SELECT * FROM decile40) AND total_accessibility >(SELECT * FROM decile35) THEN 8
                         WHEN total_accessibility <= (SELECT * FROM decile45) AND total_accessibility >(SELECT * FROM decile40) THEN 9
                         WHEN total_accessibility <= (SELECT * FROM decile50) AND total_accessibility >(SELECT * FROM decile45) THEN 10
                         WHEN total_accessibility <= (SELECT * FROM decile55) AND total_accessibility >(SELECT * FROM decile50) THEN 11
                         WHEN total_accessibility <= (SELECT * FROM decile60) AND total_accessibility >(SELECT * FROM decile55) THEN 12
                         WHEN total_accessibility <= (SELECT * FROM decile65) AND total_accessibility >(SELECT * FROM decile60) THEN 13
                         WHEN total_accessibility <= (SELECT * FROM decile70) AND total_accessibility >(SELECT * FROM decile65) THEN 14
                         WHEN total_accessibility <= (SELECT * FROM decile75) AND total_accessibility >(SELECT * FROM decile70) THEN 15
                         WHEN total_accessibility <= (SELECT * FROM decile80) AND total_accessibility >(SELECT * FROM decile75) THEN 16
                         WHEN total_accessibility <= (SELECT * FROM decile85) AND total_accessibility >(SELECT * FROM decile80) THEN 17
                         WHEN total_accessibility <= (SELECT * FROM decile90) AND total_accessibility >(SELECT * FROM decile85) THEN 18
                         WHEN total_accessibility <= (SELECT * FROM decile95) AND total_accessibility >(SELECT * FROM decile90) THEN 19
                         WHEN total_accessibility = 0 THEN 0
                         ELSE 20 END);
--- Average percentiles 
              
ALTER TABLE grid_heatmap_acc ADD COLUMN acc_numeric_per NUMERIC;
WITH averages AS(
SELECT accessibility_percentile, min(total_accessibility) AS minimum,  max(total_accessibility) AS maximum, (min(total_accessibility)+max(total_accessibility))/2 AS average FROM grid_heatmap_acc GROUP BY accessibility_percentile
)
UPDATE grid_heatmap_acc
SET acc_numeric_per = (CASE WHEN accessibility_percentile = 0 THEN 0
						    WHEN accessibility_percentile = 1 THEN (SELECT average FROM averages WHERE accessibility_percentile = 1)
						    WHEN accessibility_percentile = 2 THEN (SELECT average FROM averages WHERE accessibility_percentile = 2)
						    WHEN accessibility_percentile = 3 THEN (SELECT average FROM averages WHERE accessibility_percentile = 3)
						    WHEN accessibility_percentile = 4 THEN (SELECT average FROM averages WHERE accessibility_percentile = 4)
						    WHEN accessibility_percentile = 5 THEN (SELECT average FROM averages WHERE accessibility_percentile = 5)
						    WHEN accessibility_percentile = 6 THEN (SELECT average FROM averages WHERE accessibility_percentile = 6)
						    WHEN accessibility_percentile = 7 THEN (SELECT average FROM averages WHERE accessibility_percentile = 7)
						    WHEN accessibility_percentile = 8 THEN (SELECT average FROM averages WHERE accessibility_percentile = 8)
						    WHEN accessibility_percentile = 9 THEN (SELECT average FROM averages WHERE accessibility_percentile = 9)
						    WHEN accessibility_percentile = 10 THEN (SELECT average FROM averages WHERE accessibility_percentile = 10)
						    WHEN accessibility_percentile = 11 THEN (SELECT average FROM averages WHERE accessibility_percentile = 11)
						    WHEN accessibility_percentile = 12 THEN (SELECT average FROM averages WHERE accessibility_percentile = 12)
						    WHEN accessibility_percentile = 13 THEN (SELECT average FROM averages WHERE accessibility_percentile = 13)
						    WHEN accessibility_percentile = 14 THEN (SELECT average FROM averages WHERE accessibility_percentile = 14)
						    WHEN accessibility_percentile = 15 THEN (SELECT average FROM averages WHERE accessibility_percentile = 15)
						    WHEN accessibility_percentile = 16 THEN (SELECT average FROM averages WHERE accessibility_percentile = 16)
						    WHEN accessibility_percentile = 17 THEN (SELECT average FROM averages WHERE accessibility_percentile = 17)
						    WHEN accessibility_percentile = 18 THEN (SELECT average FROM averages WHERE accessibility_percentile = 18)
						    WHEN accessibility_percentile = 19 THEN (SELECT average FROM averages WHERE accessibility_percentile = 19)
						    WHEN accessibility_percentile = 20 THEN (SELECT average FROM averages WHERE accessibility_percentile = 20) END 
);
--- Join accessibility scores and accessibility deciles to convalidation codes

DROP TABLE IF EXISTS convalidation_codes_deciles_acc; 
SELECT cc.*, accessibility_percentile, acc_numeric_per INTO convalidation_codes_deciles_acc FROM convalidation_codes_deciles cc, grid_heatmap_acc gha WHERE cc.grid_id = gha.grid_id;

SELECT * FROM convalidation_codes_deciles_acc;
--- Indicators per Decile group
--- 1. Walking share

DROP TABLE IF EXISTS walking_share_deciles_acc;
WITH walking_trips AS (
SELECT * FROM bogota_trips WHERE study_mode = 'walking'),
walking_summary AS (
SELECT cc.accessibility_percentile, sum(bt.f_exp) AS f_exp_walking, count(study_mode) AS walking_trips FROM convalidation_codes_deciles_acc cc, walking_trips bt WHERE "Id_Hogar" = id_hogar GROUP BY cc.accessibility_percentile ORDER BY cc.accessibility_percentile),
all_summary AS (
SELECT cc.accessibility_percentile, sum(bt.f_exp) AS f_exp_all, count(study_mode) AS all_trips FROM convalidation_codes_deciles_acc cc, bogota_trips bt WHERE "Id_Hogar" = id_hogar GROUP BY cc.accessibility_percentile ORDER BY cc.accessibility_percentile)
SELECT wt.*, s.f_exp_all, s.all_trips, (wt.f_exp_walking/s.f_exp_all) AS walking_share_ef, (wt.walking_trips::numeric/s.all_trips::numeric) AS walking_share_n 
	INTO walking_share_deciles_acc FROM walking_summary wt, all_summary s WHERE wt.accessibility_percentile = s.accessibility_percentile;

--SELECT * FROM walking_share_deciles_acc;

--- 2. Trips per person
DROP TABLE IF EXISTS walking_trips_person_deciles_acc;
WITH walking_trips AS (
SELECT * FROM bogota_trips WHERE study_mode = 'walking'),
walking_summary AS (
SELECT cc.accessibility_percentile, sum(bt.f_exp) AS f_exp_walking, count(study_mode) AS walking_trips FROM convalidation_codes_deciles_acc cc, walking_trips bt WHERE "Id_Hogar" = id_hogar GROUP BY cc.accessibility_percentile ORDER BY cc.accessibility_percentile),
persons_summary AS (
SELECT cc.accessibility_percentile, sum(bmp.f_exp) AS persons_ef, count(bmp.id_hogar) AS persons_n FROM bogota_mhs_persons bmp, convalidation_codes_deciles_acc cc WHERE "Id_Hogar" = id_hogar GROUP BY cc.accessibility_percentile ORDER BY cc.accessibility_percentile)
SELECT ws.*,ps.persons_ef, ps.persons_n, (f_exp_walking/persons_ef) AS walking_trips_ef, (walking_trips::numeric/persons_n::numeric) AS walking_trips_n  
	INTO walking_trips_person_deciles_acc
	FROM walking_summary ws, persons_summary ps WHERE ws.accessibility_percentile = ps.accessibility_percentile;

SELECT * FROM walking_trips_person_deciles_acc;
--- 3. Percentage of internal trips
DROP TABLE IF EXISTS inner_zone_trips_deciles_acc;
WITH walking_trips AS (
SELECT * FROM bogota_trips WHERE study_mode = 'walking'),
self_zone AS (
SELECT cc.accessibility_percentile, sum(wt.f_exp) AS internal_ef, count(id_hogar) AS internal_n FROM walking_trips wt, convalidation_codes_deciles_acc cc WHERE "Id_Hogar" = id_hogar AND zat_origen = zat_destino GROUP BY cc.accessibility_percentile),
all_trips AS (
SELECT cc.accessibility_percentile, sum(wt.f_exp) AS all_trips_ef, count(id_hogar) AS all_trips_n FROM walking_trips wt, convalidation_codes_deciles_acc cc WHERE "Id_Hogar" = id_hogar AND zat_origen IS NOT NULL GROUP BY cc.accessibility_percentile
)
SELECT s.accessibility_percentile, internal_ef, internal_n, all_trips_ef, all_trips_n, (internal_ef/all_trips_ef) AS share_internal_trips_ef, (internal_n::numeric/all_trips_n::numeric) AS share_internal_trips_n 
	INTO inner_zone_trips_deciles_acc
	FROM self_zone s, all_trips a WHERE s.accessibility_percentile = a.accessibility_percentile;

SELECT * FROM inner_zone_trips_deciles_acc;
--- 4. No of different zats in destinations
DROP TABLE IF EXISTS amount_of_destinations_deciles_acc;
WITH walking_trips AS (
SELECT * FROM bogota_trips WHERE study_mode = 'walking'),
destinations AS (
SELECT cc.zat, zat_destino, f_exp, cc.accessibility_percentile FROM  walking_trips wt, convalidation_codes_deciles_acc cc WHERE "Id_Hogar" = id_hogar AND zat_destino IS NOT null
),
counter AS (
SELECT DISTINCT accessibility_percentile, zat, zat_destino FROM destinations ORDER BY zat, zat_destino
), sumup AS (
SELECT accessibility_percentile, zat, count(zat_destino) AS no_of_dest_zat FROM counter GROUP BY zat, accessibility_percentile)
SELECT accessibility_percentile, avg(no_of_dest_zat) AS no_of_dest_zat INTO amount_of_destinations_deciles_acc FROM sumup GROUP BY accessibility_percentile;

SELECT * FROM amount_of_destinations_deciles_acc;
--- 5. Walking trips for disabled persons
DROP TABLE IF EXISTS walking_trips_disabled_deciles_acc;

WITH walking_trips AS (
SELECT id_hogar, id_persona, count(id_persona) AS trips_n, sum(f_exp) AS trips_ef FROM bogota_trips WHERE study_mode = 'walking' GROUP BY id_hogar, id_persona),
disabled_persons AS (
SELECT * FROM bogota_mhs_persons WHERE p8_id_dificultad_fisica_1 = 1 OR
									   p8_id_dificultad_fisica_2 = 1),
persons_with_trips AS (
SELECT dp.*, trips_n, trips_ef FROM disabled_persons dp
LEFT JOIN walking_trips wp ON dp.id_hogar = wp.id_hogar AND dp.id_persona = wp.id_persona
)
SELECT cc.accessibility_percentile, count(pwt.f_exp) AS persons_n, sum(pwt.f_exp) AS persons_ef, sum(trips_n) AS trips_n, sum(trips_ef) AS trips_ef, (sum(trips_ef)/sum(pwt.f_exp)) AS trips_person_ef, 
	(sum(trips_n)/count(pwt.f_exp)) AS trips_person_n 
	INTO walking_trips_disabled_deciles_acc
	FROM persons_with_trips pwt, convalidation_codes_deciles_acc cc 
	WHERE pwt.id_hogar = "Id_Hogar" AND  cc.zat IS NOT NULL GROUP BY cc.accessibility_percentile;

--- 6. % Of driver's licences ownership
DROP TABLE IF EXISTS drivers_licenses_deciles_acc;
WITH people_with_license AS (
SELECT * FROM bogota_mhs_persons WHERE p4_edad >=18 AND ("p10_licencia_conduccion_1" = 1 OR "p10_Licencia_conduccion_2" = 1 OR "p10_Licencia_conduccion_3" = 1)
),
all_major_people AS (
SELECT * FROM bogota_mhs_persons WHERE p4_edad >=18
), 
people_join AS (
SELECT amp.*, pwl.f_exp AS f_exp_license FROM all_major_people amp
LEFT JOIN people_with_license pwl ON amp.id_hogar = pwl.id_hogar)
SELECT cc.accessibility_percentile, sum(f_exp) AS all_ef, count(f_exp) AS all_n, sum(f_exp_license) AS license_ef, count(f_exp_license) AS license_n, (sum(f_exp_license)/sum(f_exp)) AS lic_pers_ef, (count(f_exp_license)::numeric/count(f_exp)::numeric) AS lic_pers_n
	INTO drivers_licenses_deciles_acc
	FROM convalidation_codes_deciles_acc cc, people_join pj 
	WHERE cc."Id_Hogar" = id_hogar GROUP BY cc.accessibility_percentile ORDER BY lic_pers_n desc;

--- 7. Vehicle ownership
DROP TABLE IF EXISTS vehicle_ownership_deciles_acc;

WITH no_vehicles AS (
SELECT "Id_Hogar" AS id_hogar,p8_mayores_cinco_anios AS persons_above_5, (p1mc_automovil + p1mc_pickup + p1mc_motocicleta + p1mc_moto_carro + p1mc_triciclo_moto) AS all_vehicles, "Factor" FROM bogota_mhs_households
)
SELECT cc.accessibility_percentile, sum(all_vehicles) AS vehicles, sum(persons_above_5) AS persons, (sum(all_vehicles)/sum(persons_above_5)*1000) AS mot_rate 
	INTO vehicle_ownership_deciles_acc 
	FROM no_vehicles nv, convalidation_codes_deciles_acc cc 
	WHERE nv.id_hogar = "Id_Hogar" AND cc.zat IS NOT NULL GROUP BY cc.accessibility_percentile ORDER BY mot_rate desc;
SELECT * FROM vehicle_ownership_deciles_acc ORDER BY accessibility_percentile;

--- 8. Average walking time
DROP TABLE IF EXISTS walking_time_deciles_acc;
WITH walking_trips AS (
SELECT *, (p31_hora_llegada::numeric - hora_inicio_viaje::numeric) AS t_time FROM bogota_trips WHERE study_mode = 'walking' ),
walking_trips_filtered AS (
SELECT * FROM walking_trips WHERE t_time <= (1::NUMERIC /48::numeric) AND t_time >0 ORDER BY t_time
)
SELECT cc.accessibility_percentile, avg(t_time)*(24*60) AS t_time_min , count(t_time) AS sample 
	INTO walking_time_deciles_acc	
	FROM walking_trips_filtered wtf, convalidation_codes_deciles_acc cc 
	WHERE wtf.id_hogar = "Id_Hogar" GROUP BY cc.accessibility_percentile;
SELECT * FROM walking_time_deciles_acc ORDER BY accessibility_percentile;

--- Join
SELECT * FROM grid_heatmap_acc;
DROP TABLE IF EXISTS table_for_model_deciles_acc;
WITH areas_acc AS (
SELECT accessibility_percentile ,acc_numeric_per , ST_union(geom) AS geom FROM grid_heatmap_acc GROUP BY accessibility_percentile , acc_numeric_per
),
ind_1 AS (
SELECT ht.*, walking_share_ef, walking_share_n FROM areas_acc ht
LEFT JOIN walking_share_deciles_acc ws ON ht.accessibility_percentile = ws.accessibility_percentile),
ind_2 AS (
SELECT ht.*, walking_trips_ef, walking_trips_n FROM ind_1 ht
LEFT JOIN walking_trips_person_deciles_acc wtp ON ht.accessibility_percentile = wtp.accessibility_percentile),
ind_3 AS (
SELECT ht.*, share_internal_trips_ef, share_internal_trips_n FROM ind_2 ht
LEFT JOIN inner_zone_trips_deciles_acc izt ON ht.accessibility_percentile = izt.accessibility_percentile ),
ind_4 AS (
SELECT ht.*, no_of_dest_zat FROM ind_3 ht
LEFT JOIN amount_of_destinations_deciles_acc aod ON ht.accessibility_percentile = aod.accessibility_percentile),
ind_5 AS (
SELECT ht.*, trips_person_ef AS trips_person_disabled_ef, trips_person_n AS trips_person_disabled_n FROM ind_4 ht
LEFT JOIN walking_trips_disabled_deciles_acc wtd ON ht.accessibility_percentile = wtd.accessibility_percentile),
ind_6 AS (
SELECT ht.*, lic_pers_ef, lic_pers_n FROM ind_5 ht
LEFT JOIN drivers_licenses_deciles_acc dl ON ht.accessibility_percentile = dl.accessibility_percentile),
ind_7 AS (
SELECT ht.*, mot_rate FROM ind_6 ht
LEFT JOIN vehicle_ownership_deciles_acc vo ON ht.accessibility_percentile = vo.accessibility_percentile)
SELECT ht.*, t_time_min, sample INTO table_for_model_deciles_acc FROM ind_7 ht
LEFT JOIN walking_time_deciles_acc wt ON ht.accessibility_percentile = wt.accessibility_percentile;


DELETE FROM table_for_model_deciles
WHERE numeric_deciles = 0;








