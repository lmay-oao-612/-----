-- 1. 初始化 PostGIS 空间扩展
CREATE EXTENSION IF NOT EXISTS postgis;

-- 2. 清理旧表
DROP TABLE IF EXISTS disposal_record CASCADE;
DROP TABLE IF EXISTS violation_event CASCADE;
DROP TABLE IF EXISTS telemetry CASCADE;
DROP TABLE IF EXISTS flight_track CASCADE;
DROP TABLE IF EXISTS flight_mission CASCADE;
DROP TABLE IF EXISTS takeoff_landing_site CASCADE;
DROP TABLE IF EXISTS nofly_zone CASCADE;
DROP TABLE IF EXISTS authority CASCADE;
DROP TABLE IF EXISTS pilot_drone CASCADE;
DROP TABLE IF EXISTS pilot CASCADE;
DROP TABLE IF EXISTS drone CASCADE;
DROP TABLE IF EXISTS organization CASCADE;

-- =====================================================================
-- 实体建表
-- =====================================================================

-- (1) Organization 单位表 (非空间属性表)
CREATE TABLE organization (
    org_id serial PRIMARY KEY,
    name varchar(100) NOT NULL UNIQUE,
    type varchar(50) NOT NULL, -- 如：企业、政府机构、事业单位
    contact varchar(100) NOT NULL
);

COMMENT ON TABLE organization IS '无人机所属单位/企业档案表';
COMMENT ON COLUMN organization.org_id IS '单位ID，自增主键';
COMMENT ON COLUMN organization.name IS '单位名称';
COMMENT ON COLUMN organization.type IS '单位类型';
COMMENT ON COLUMN organization.contact IS '联系人电话或方式';

-- (2) Drone 无人机表 (非空间属性表)
CREATE TABLE drone (
    drone_id serial PRIMARY KEY,
    model varchar(50) NOT NULL,
    owner_org_id integer NOT NULL,
    max_height real NOT NULL CONSTRAINT chk_drone_max_height CHECK (max_height > 0), -- 最大物理飞行限高(米)
    status varchar(20) NOT NULL, -- 如：在运、维护、报废
    CONSTRAINT fk_drone_org FOREIGN KEY (owner_org_id) 
        REFERENCES organization(org_id) ON DELETE RESTRICT ON UPDATE CASCADE
);

COMMENT ON TABLE drone IS '被监管的飞行器（无人机）设备登记表';
COMMENT ON COLUMN drone.owner_org_id IS '所属单位ID，外键';
COMMENT ON COLUMN drone.max_height IS '设计最大允许飞行高度（米）';

-- (3) Pilot 飞手表 (非空间属性表)
CREATE TABLE pilot (
    pilot_id serial PRIMARY KEY,
    name varchar(50) NOT NULL,
    license_no varchar(50) NOT NULL UNIQUE,
    phone varchar(20) NOT NULL UNIQUE
);

COMMENT ON TABLE pilot IS '无人机操控人员（飞手）档案表';
COMMENT ON COLUMN pilot.license_no IS '飞手执照编号，唯一';

-- (4) Pilot_Drone 飞手与无人机授权中间表 (多对多授权关系表)
CREATE TABLE pilot_drone (
    pilot_id integer NOT NULL,
    drone_id integer NOT NULL,
    PRIMARY KEY (pilot_id, drone_id),
    CONSTRAINT fk_pd_pilot FOREIGN KEY (pilot_id) 
        REFERENCES pilot(pilot_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_pd_drone FOREIGN KEY (drone_id) 
        REFERENCES drone(drone_id) ON DELETE CASCADE ON UPDATE CASCADE
);

COMMENT ON TABLE pilot_drone IS '飞手与无人机多对多授权绑定中间表';

-- (5) TakeoffLandingSite 起降点表 (2D空间点要素表)
CREATE TABLE takeoff_landing_site (
    site_id serial PRIMARY KEY,
    name varchar(100) NOT NULL UNIQUE,
    site_type varchar(50) NOT NULL, -- 如：楼顶起降场、简易场地、垂直起降机场
    geom geometry(Point, 4326) NOT NULL -- 起降点二维坐标 (WGS 84)
);

COMMENT ON TABLE takeoff_landing_site IS '登记的无人机起降场地表';
COMMENT ON COLUMN takeoff_landing_site.geom IS '起降场地的地理点坐标 (WGS 84)';

-- (6) FlightMission 飞行任务表 (时空空间表 - 可包含计划范围Polygon)
CREATE TABLE flight_mission (
    mission_id serial PRIMARY KEY,
    drone_id integer NOT NULL,
    pilot_id integer NOT NULL,
    start_time timestamp with time zone NOT NULL,
    end_time timestamp with time zone NOT NULL,
    purpose varchar(100) NOT NULL,
    status varchar(20) NOT NULL DEFAULT '待审批', -- 待审批、已批准、执行中、已结束
    planned_area geometry(Polygon, 4326), -- 计划范围面要素，可为空
    start_site_id integer NOT NULL, -- 起点，外键
    end_site_id integer NOT NULL,   -- 终点，外键
    CONSTRAINT fk_mission_drone FOREIGN KEY (drone_id)
        REFERENCES drone(drone_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_mission_pilot FOREIGN KEY (pilot_id)
        REFERENCES pilot(pilot_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_mission_start_site FOREIGN KEY (start_site_id)
        REFERENCES takeoff_landing_site(site_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_mission_end_site FOREIGN KEY (end_site_id)
        REFERENCES takeoff_landing_site(site_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_mission_time CHECK (end_time > start_time),
    CONSTRAINT chk_mission_status CHECK (status IN ('待审批', '已批准', '执行中', '已结束'))
);

COMMENT ON TABLE flight_mission IS '飞行任务申请及计划信息表';
COMMENT ON COLUMN flight_mission.planned_area IS '申报任务飞行的规划限制面范围 (WGS 84，可为空)';

-- (7) FlightTrack 飞行轨迹表 (空间线要素表)
CREATE TABLE flight_track (
    track_id serial PRIMARY KEY,
    mission_id integer NOT NULL,
    avg_altitude real NOT NULL CONSTRAINT chk_track_avg_alt CHECK (avg_altitude >= 0),
    max_altitude real NOT NULL CONSTRAINT chk_track_max_alt CHECK (max_altitude >= avg_altitude),
    geom geometry(LineString, 4326) NOT NULL, -- 实际飞行轨迹线 (WGS 84)
    CONSTRAINT fk_track_mission FOREIGN KEY (mission_id)
        REFERENCES flight_mission(mission_id) ON DELETE CASCADE ON UPDATE CASCADE
);

COMMENT ON TABLE flight_track IS '任务执行中生成的实际雷达/轨迹线表';
COMMENT ON COLUMN flight_track.geom IS '实际执行任务轨迹的二维折线 (WGS 84)';

-- (8) Telemetry 遥测点表 (高频时空点要素表)
CREATE TABLE telemetry (
    telemetry_id bigserial PRIMARY KEY, -- 防溢出
    mission_id integer NOT NULL,
    time timestamp with time zone NOT NULL, -- 上报时间
    altitude real NOT NULL CONSTRAINT chk_telemetry_alt CHECK (altitude >= 0), -- 上报海拔高度(米)
    speed real NOT NULL CONSTRAINT chk_telemetry_speed CHECK (speed >= 0), -- 瞬时速度(米/秒)
    geom geometry(Point, 4326) NOT NULL, -- 上报瞬时地理点
    CONSTRAINT fk_telemetry_mission FOREIGN KEY (mission_id)
        REFERENCES flight_mission(mission_id) ON DELETE CASCADE ON UPDATE CASCADE
);

COMMENT ON TABLE telemetry IS '无人机实时状态与遥测位置记录表';
COMMENT ON COLUMN telemetry.geom IS '遥测上报二维地理点坐标 (WGS 84)';

-- (9) NoFlyZone 禁飞/限飞区表 (时空空间多边形面表)
CREATE TABLE nofly_zone (
    zone_id serial PRIMARY KEY,
    name varchar(100) NOT NULL,
    zone_type varchar(50) NOT NULL, -- 机场管制区、重点单位禁飞区、临时活动管制区等
    height_limit real NOT NULL CONSTRAINT chk_zone_height CHECK (height_limit >= 0), -- 垂直限高
    valid_from timestamp with time zone NOT NULL, -- 启用时间
    valid_to timestamp with time zone NOT NULL,   -- 失效时间
    geom geometry(Polygon, 4326) NOT NULL, -- 管制面要素 (WGS 84)
    CONSTRAINT chk_zone_time CHECK (valid_to > valid_from)
);

COMMENT ON TABLE nofly_zone IS '动态时空管制禁飞/限飞空域表';
COMMENT ON COLUMN nofly_zone.geom IS '管制区域多边形边界 (WGS 84)';

-- (10) Authority 监管部门表 (空间多边形面表)
CREATE TABLE authority (
    authority_id serial PRIMARY KEY,
    name varchar(100) NOT NULL UNIQUE,
    level varchar(50) NOT NULL, -- 市级、省级、国家级
    jurisdiction geometry(Polygon, 4326) -- 行政管辖边界空间范围，允许无
);

COMMENT ON TABLE authority IS '行业及地方低空监管部门表';
COMMENT ON COLUMN authority.jurisdiction IS '机构管辖区域的二维多边形空间面要素 (WGS 84)';

-- (11) ViolationEvent 违规事件表 (时空空间点要素表)
CREATE TABLE violation_event (
    event_id serial PRIMARY KEY,
    mission_id integer, -- 允许为空（如黑飞时无关联飞行任务）
    type varchar(50) NOT NULL, -- 超高飞行、入侵禁飞区、未经审批黑飞、无证飞行等
    time timestamp with time zone NOT NULL, -- 发生时间
    severity varchar(20) NOT NULL, -- 轻微、一般、严重
    geom geometry(Point, 4326) NOT NULL, -- 违规地理坐标点
    CONSTRAINT fk_violation_mission FOREIGN KEY (mission_id)
        REFERENCES flight_mission(mission_id) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT chk_violation_severity CHECK (severity IN ('轻微', '一般', '严重'))
);

COMMENT ON TABLE violation_event IS '低空违规飞行与异常事件报警表';

-- (12) DisposalRecord 处置记录表 (非空间属性表)
CREATE TABLE disposal_record (
    record_id serial PRIMARY KEY,
    event_id integer NOT NULL,
    authority_id integer NOT NULL,
    action varchar(100) NOT NULL, -- 警告、罚款、扣留设备、吊销执照
    result varchar(255) NOT NULL, -- 处置处理结果
    time timestamp with time zone NOT NULL, -- 处置发生时间
    CONSTRAINT fk_disposal_event FOREIGN KEY (event_id)
        REFERENCES violation_event(event_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_disposal_auth FOREIGN KEY (authority_id)
        REFERENCES authority(authority_id) ON DELETE RESTRICT ON UPDATE CASCADE
);

COMMENT ON TABLE disposal_record IS '违规事件执法与处置记录表';

-- =====================================================================
-- 建立高级索引设计 
-- =====================================================================

-- 二维地理坐标 GiST 空间索引 (大幅度提高空间拓扑判断效率，如 ST_Intersects, ST_Contains)
CREATE INDEX idx_site_geom ON takeoff_landing_site USING gist(geom);
CREATE INDEX idx_mission_area ON flight_mission USING gist(planned_area);
CREATE INDEX idx_track_geom ON flight_track USING gist(geom);
CREATE INDEX idx_telemetry_geom ON telemetry USING gist(geom);
CREATE INDEX idx_nofly_geom ON nofly_zone USING gist(geom);
CREATE INDEX idx_authority_juris ON authority USING gist(jurisdiction);
CREATE INDEX idx_violation_geom ON violation_event USING gist(geom);

-- 时空/高频时间检索 B-Tree 索引 (支持时间段的高效检索截断)
CREATE INDEX idx_mission_time ON flight_mission(start_time, end_time);
CREATE INDEX idx_telemetry_time ON telemetry(time);
CREATE INDEX idx_nofly_validity ON nofly_zone(valid_from, valid_to);
CREATE INDEX idx_violation_time ON violation_event(time);
CREATE INDEX idx_disposal_time ON disposal_record(time);

-- 联合优化复合索引 (专为遥测查询和历史轨迹回放优化，避免百万轨迹全表扫描)
CREATE INDEX idx_telemetry_mission_time ON telemetry (mission_id, time DESC);
CREATE INDEX idx_track_mission_id ON flight_track (mission_id);
