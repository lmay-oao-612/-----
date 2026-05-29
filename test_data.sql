BEGIN;

-- 1. 插入单位档案 (Organization)
INSERT INTO organization (name, type, contact) VALUES
('顺丰低空物流有限公司', '企业', '0755-88881234'),
('深圳市国能电力巡检有限公司', '企业', '0755-99995678'),
('个人兴趣玩家联盟', '社会团体', '13800000000');

-- 2. 插入无人机设备 (Drone - 物理高度上限约束)
INSERT INTO drone (model, owner_org_id, max_height, status) VALUES
('丰翼丰舟-90', 1, 300.0, '在运'), -- drone_id: 1
('丰翼八轴-20', 1, 200.0, '在运'), -- drone_id: 2
('大疆经纬M350 RTK', 2, 120.0, '在运'), -- drone_id: 3
('DJI Phantom 4 Pro', 3, 120.0, '在运'); -- drone_id: 4

-- 3. 插入飞手档案 (Pilot)
INSERT INTO pilot (name, license_no, phone) VALUES
('飞手甲', 'UAV-PL-20260001', '13800000001'), -- pilot_id: 1
('飞手乙', 'UAV-PL-20260002', '13800000002'), -- pilot_id: 2
('张三', 'UAV-PL-20269999', '13800000003');  -- pilot_id: 3

-- 4. 建立飞手与无人机的多对多授权绑定 (Pilot_Drone 中间表)
INSERT INTO pilot_drone (pilot_id, drone_id) VALUES
(1, 1), -- 飞手甲 授权操作 丰舟-90
(1, 2), -- 飞手甲 授权操作 八轴-20
(2, 2), -- 飞手乙 授权操作 八轴-20
(2, 3), -- 飞手乙 授权操作 电力巡检机
(3, 4); -- 张三 授权操作 其个人航拍机

-- 5. 插入起降场地 (TakeoffLandingSite - 二维空间点)
INSERT INTO takeoff_landing_site (name, site_type, geom) VALUES
('南山科技园楼顶起降场', '楼顶起降点', ST_GeomFromText('POINT(113.94 22.54)', 4326)), -- site_id: 1
('前海自贸区物流集散起降点', '楼顶起降点', ST_GeomFromText('POINT(113.90 22.52)', 4326)), -- site_id: 2
('深圳北站应急起降简易场地', '简易场地', ST_GeomFromText('POINT(114.03 22.61)', 4326)); -- site_id: 3

-- 6. 插入飞行任务申报 (FlightMission - 二维限制面 Polygon + 起降点关联)
-- 任务 1: 正常物流配送（南山-前海，高度50-150m，已获批准，有 planned_area 保护空域）
-- 任务 2: 大运周边配送任务（大运体育馆附近，大范围测试，将与演唱会临时禁飞区重叠冲突）
-- 任务 3: 张三起降申报
INSERT INTO flight_mission (drone_id, pilot_id, start_time, end_time, purpose, status, planned_area, start_site_id, end_site_id) VALUES
(1, 1, '2026-05-28 13:00:00+08', '2026-05-28 14:00:00+08', '南山前海大闸蟹快捷物流配送', '执行中',
 ST_GeomFromText('POLYGON((113.88 22.50, 113.96 22.50, 113.96 22.56, 113.88 22.56, 113.88 22.50))', 4326), 1, 2),

(2, 2, '2026-05-28 15:00:00+08', '2026-05-28 16:00:00+08', '大运中心周边快件干线测试飞行', '已批准',
 ST_GeomFromText('POLYGON((114.15 22.65, 114.28 22.65, 114.28 22.75, 114.15 22.75, 114.15 22.65))', 4326), 3, 2),

(4, 3, '2026-05-28 09:00:00+08', '2026-05-28 10:00:00+08', '南山人才公园个人摄影创作航拍', '已结束',
 ST_GeomFromText('POLYGON((113.91 22.57, 113.94 22.57, 113.94 22.60, 113.91 22.60, 113.91 22.57))', 4326), 1, 1);

-- 7. 插入实际飞行轨迹 (FlightTrack - 空间线要素 LINESTRING)
INSERT INTO flight_track (mission_id, avg_altitude, max_altitude, geom) VALUES
(1, 120.0, 350.0, ST_GeomFromText('LINESTRING(113.94 22.54, 113.92 22.53, 113.90 22.52)', 4326)); -- 轨迹1：从南山飞往前海

-- 8. 插入遥测点高频轨迹数据 (Telemetry - 空间点要素 + 关联任务)
-- 任务 1 (顺丰丰舟90) 的五次连续正常上报点
INSERT INTO telemetry (mission_id, time, altitude, speed, geom) VALUES
(1, '2026-05-28 13:05:00+08', 100.0, 12.5, ST_GeomFromText('POINT(113.94 22.54)', 4326)),
(1, '2026-05-28 13:06:00+08', 105.0, 12.4, ST_GeomFromText('POINT(113.93 22.535)', 4326)),
(1, '2026-05-28 13:07:00+08', 108.0, 12.6, ST_GeomFromText('POINT(113.92 22.53)', 4326)),
(1, '2026-05-28 13:08:00+08', 102.0, 12.3, ST_GeomFromText('POINT(113.91 22.525)', 4326)),
(1, '2026-05-28 13:09:00+08', 100.0, 12.5, ST_GeomFromText('POINT(113.90 22.52)', 4326)),
-- 13:10:00 突发故障超高飞行达到 350米 (超出无人机设计限高300米，触发高度越界违规)
(1, '2026-05-28 13:10:00+08', 350.0, 14.1, ST_GeomFromText('POINT(113.89 22.515)', 4326));

-- 张三个人无人机，在福田市民中心起飞上报（不对应有效飞行任务，代表非法黑飞，落入禁飞区）
INSERT INTO telemetry (mission_id, time, altitude, speed, geom) VALUES
(3, '2026-05-28 12:45:00+08', 80.0, 5.5, ST_GeomFromText('POINT(114.04 22.535)', 4326)),
-- 12:46:00 轨迹入侵福田市民中心多边形禁飞区
(3, '2026-05-28 12:46:00+08', 150.0, 6.0, ST_GeomFromText('POINT(114.055 22.540)', 4326));

-- 9. 插入管制空域 (NoFlyZone - 时空空间多边形)
INSERT INTO nofly_zone (name, zone_type, height_limit, valid_from, valid_to, geom) VALUES
('深圳市福田市民中心核心禁飞区', '重点单位禁飞区', 1000.0, 
 '2026-01-01 00:00:00+08', '2036-01-01 00:00:00+08', 
 ST_GeomFromText('POLYGON((114.05 22.53, 114.07 22.53, 114.07 22.55, 114.05 22.55, 114.05 22.53))', 4326)),

('龙岗体育馆大型演唱会临时禁飞区', '临时活动管制区', 600.0, 
 '2026-05-28 14:00:00+08', '2026-05-28 22:00:00+08', 
 ST_GeomFromText('POLYGON((114.20 22.68, 114.23 22.68, 114.23 22.71, 114.20 22.71, 114.20 22.68))', 4326));

-- 10. 插入监管部门档案 (Authority - 空间多边形)
INSERT INTO authority (name, level, jurisdiction) VALUES
('深圳市低空经济联合监管局', '市级', 
 ST_GeomFromText('POLYGON((113.7 22.4, 114.5 22.4, 114.5 22.9, 113.7 22.9, 113.7 22.4))', 4326));

-- 11. 插入违规事件 (ViolationEvent - 时空空间点)
INSERT INTO violation_event (mission_id, type, time, severity, geom) VALUES
-- 违规 1: 顺丰遥测爬升超高 (触发于 13:10:00)
(1, '高度超限违规', '2026-05-28 13:10:00+08', '严重', ST_GeomFromText('POINT(113.89 22.515)', 4326)),
-- 违规 2: 张三航拍机入侵禁飞区 (触发于 12:46:00)
(3, '侵入禁飞区', '2026-05-28 12:46:00+08', '严重', ST_GeomFromText('POINT(114.055 22.540)', 4326));

-- 12. 插入处置记录 (DisposalRecord - 对接执法流程)
INSERT INTO disposal_record (event_id, authority_id, action, result, time) VALUES
(1, 1, '警告并责令立刻下降高度', '飞手遵从指挥并返航，扣罚运营企业信用分10分', '2026-05-28 13:15:00+08'),
(2, 1, '民警现场查扣飞行设备', '对违规飞手张三处以行政罚款500元并暂扣无人机', '2026-05-28 13:00:00+08');

COMMIT;
