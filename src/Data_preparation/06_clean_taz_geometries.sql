--- GOAT clean taz data

ALTER TABLE taz ADD geom2d geometry;
UPDATE taz SET geom2d = ST_Force2D(geom);
ALTER TABLE taz DROP COLUMN geom;
ALTER TABLE taz ADD geom geometry;
UPDATE taz SET geom = geom2d;
ALTER TABLE taz DROP geom2d;
SELECT gid, area, muncod, nommun, zat, utam, (ST_Dump(geom)).geom::geometry AS geom FROM taz;
SELECT DISTINCT ST_GeometryType(geom) FROM taz;