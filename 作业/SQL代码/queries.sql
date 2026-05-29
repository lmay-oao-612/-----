-- =====================================================================
-- 场景一：飞行任务申报冲突检测（面与面时空间交叠/相交查询）
-- 监管逻辑：当飞手或单位申报飞行任务时，系统自动核查申报的计划飞行空域范围（planned_area 面）
--           是否在计划执行时间内（start_time 至 end_time）穿过了设立的禁飞管制空域（nofly_zone 面）。
-- PostGIS 算子：ST_Intersects（空间多边形相交） + 边界时间窗口重叠
-- =====================================================================
SELECT 
    fm.mission_id AS 任务ID,
    d.model AS 无人机型号,
    p.name AS 执飞飞手,
    fm.purpose AS 任务目的,
    n.name AS 冲突管制区,
    n.zone_type AS 管制类型,
    fm.start_time AS 计划开始时间,
    fm.end_time AS 计划结束时间
FROM flight_mission fm
JOIN drone d ON fm.drone_id = d.drone_id
JOIN pilot p ON fm.pilot_id = p.pilot_id
JOIN nofly_zone n ON ST_Intersects(fm.planned_area, n.geom) -- 空间面与面相交
WHERE n.zone_type = '临时活动管制区'
  -- 时间重叠：任务申报时间与管制区间发生交叠
  AND n.valid_to > fm.start_time 
  AND n.valid_from < fm.end_time;

-- 验证说明：该查询将成功筛查出 任务 2 (mission_id: 2)，因为其申报的龙岗飞行限制面 (planned_area) 
--           与大运中心临时禁飞管制区 (nofly_zone) 在 5月28日 15:00-16:00 发生重叠冲突。


-- =====================================================================
-- 场景二：实时遥测轨迹侵入禁飞区警报（动态电子围栏监测）
-- 监管逻辑：无人机上报实时遥测坐标点。系统检索在当前时刻，有哪些无人机的遥测位置（geom 点）
--           落入了正处于生效管制时间内的禁飞区（geom 面）内部，且高度也在其限高范围内。
-- PostGIS 算子：ST_Contains（多边形面包含地理点）
-- =====================================================================
SELECT 
    t.telemetry_id AS 遥测记录ID,
    p.name AS 操控飞手,
    d.model AS 无人机型号,
    n.name AS 侵入管制区,
    t.altitude AS 当前上报高度_米,
    n.height_limit AS 管制高度_米,
    t.time AS 侵入时间
FROM telemetry t
JOIN flight_mission fm ON t.mission_id = fm.mission_id
JOIN pilot p ON fm.pilot_id = p.pilot_id
JOIN drone d ON fm.drone_id = d.drone_id
JOIN nofly_zone n ON ST_Contains(n.geom, t.geom) -- 空间包含关系
WHERE t.time BETWEEN n.valid_from AND n.valid_to -- 时间处于管制内
  AND t.altitude <= n.height_limit; -- 高度在管制层内

-- 验证说明：该查询会精准抓取到 飞手张三的无人机 在 12:46:00 时的轨迹点，当时该点闯入了福田市民中心核心禁飞区。


-- =====================================================================
-- 场景三：遥测高度超限违规检测（超出无人机物理设计高度上限）
-- 监管逻辑：每个无人机设备在注册时都设定了物理设计最大飞行高度（drone.max_height）。
--           当其实时上报的海拔高度（telemetry.altitude）大于设备最大安全升限时，即判定为高度越界违规。
-- 关联关系：Telemetry -> FlightMission -> Drone -> Organization
-- =====================================================================
SELECT 
    t.telemetry_id AS 遥测点ID,
    d.model AS 飞行器型号,
    o.name AS 所属单位,
    t.altitude AS 实时上报高度_米,
    d.max_height AS 物理安全高度上限_米,
    (t.altitude - d.max_height) AS 越限差值_米,
    t.time AS 违规时间戳
FROM telemetry t
JOIN flight_mission fm ON t.mission_id = fm.mission_id
JOIN drone d ON fm.drone_id = d.drone_id
JOIN organization o ON d.owner_org_id = o.org_id
WHERE t.altitude > d.max_height; -- 超过物理设计升限

-- 验证说明：该查询能成功抓取出顺丰无人机 (UAV 1) 在 13:10:00 突飞爬升至 350米 的遥测记录，超出了该机 300米 的物理飞行升限。


-- =====================================================================
-- 场景四：处置与执法闭环综合分析统计（非空间与时空业务大联动）
-- 监管逻辑：对违规异常事件及监管处置结果进行大跨度多表统计分析，
--           呈现单位、飞手、设备、违规详情、执法部门、处罚动作及结果的完整业务闭环。
-- =====================================================================
SELECT 
    o.name AS 违规单位,
    p.name AS 责任飞手,
    d.model AS 涉事机型,
    ve.type AS 违规事件类型,
    ve.time AS 违规发生时间,
    a.name AS 处置部门,
    dr.action AS 执法措施,
    dr.result AS 处置执行结果,
    dr.time AS 处置办结时间
FROM violation_event ve
LEFT JOIN flight_mission fm ON ve.mission_id = fm.mission_id
LEFT JOIN pilot p ON fm.pilot_id = p.pilot_id
LEFT JOIN drone d ON fm.drone_id = d.drone_id
LEFT JOIN organization o ON d.owner_org_id = o.org_id
JOIN disposal_record dr ON ve.event_id = dr.event_id
JOIN authority a ON dr.authority_id = a.authority_id
ORDER BY ve.time DESC;

-- 验证说明：该查询将以时间倒序输出处罚记录，展现从违规事件报警到监管局做出处罚警告/行政拘留查扣设备的完整法治闭环监管。
