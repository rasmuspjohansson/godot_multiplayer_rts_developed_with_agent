extends Node
## Periodic performance markers for server and clients.
## Server: TEST_PERF_TICK_MS (World physics callback cost + sim step time), clients:
## TEST_PERF_FRAME_MS (process frame time, physics cost, sim step time) + net bytes/s.

const REPORT_INTERVAL := 5.0

var _accum := 0.0
var _phys_sum := 0.0
var _phys_max := 0.0
var _phys_n := 0
var _frame_sum := 0.0
var _frame_max := 0.0
var _frame_n := 0
var _unit_count_cb: Callable = Callable()
var _sim_ms_sum := 0.0
var _sim_ms_max := 0.0
var _sim_n := 0

func set_unit_count_callback(cb: Callable) -> void:
	_unit_count_cb = cb

## Optional: returns extra "key=value" text appended to the client perf line.
var _extra_cb: Callable = Callable()
func set_extra_stats_callback(cb: Callable) -> void:
	_extra_cb = cb

## Optional: sim code reports its own step time so we can separate it from engine physics.
func record_sim_step_ms(ms: float) -> void:
	_sim_ms_sum += ms
	_sim_ms_max = maxf(_sim_ms_max, ms)
	_sim_n += 1

## World reports the wall time of its own _physics_process body (sim step + after-tick work).
func record_physics_ms(ms: float) -> void:
	_phys_sum += ms
	_phys_max = maxf(_phys_max, ms)
	_phys_n += 1

func _process(delta: float) -> void:
	var ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_frame_sum += ms
	_frame_max = maxf(_frame_max, ms)
	_frame_n += 1
	_accum += delta
	if _accum < REPORT_INTERVAL:
		return
	_accum = 0.0
	_report()

func _net_bytes_received_and_reset() -> int:
	var peer = multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer:
		var host: ENetConnection = (peer as ENetMultiplayerPeer).host
		if host != null:
			return int(host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA))
	return 0

func _net_bytes_sent_and_reset() -> int:
	var peer = multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer:
		var host: ENetConnection = (peer as ENetMultiplayerPeer).host
		if host != null:
			return int(host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA))
	return 0

func _report() -> void:
	var units := -1
	if _unit_count_cb.is_valid():
		units = int(_unit_count_cb.call())
	var phys_avg := _phys_sum / float(maxi(_phys_n, 1))
	var frame_avg := _frame_sum / float(maxi(_frame_n, 1))
	var sim_avg := _sim_ms_sum / float(maxi(_sim_n, 1))
	var sim_hz := float(_sim_n) / REPORT_INTERVAL
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var mem_mb := Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)
	var rx_kbs := float(_net_bytes_received_and_reset()) / REPORT_INTERVAL / 1024.0
	var tx_kbs := float(_net_bytes_sent_and_reset()) / REPORT_INTERVAL / 1024.0
	if multiplayer.is_server():
		print("TEST_PERF_TICK_MS avg=%.2f max=%.2f sim_avg=%.2f sim_max=%.2f sim_hz=%.1f fps=%.0f units=%d mem_mb=%.0f tx_kbs=%.1f" % [
			phys_avg, _phys_max, sim_avg, _sim_ms_max, sim_hz, fps, units, mem_mb, tx_kbs
		])
	else:
		var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		var draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var eng_phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var extra := ""
		if _extra_cb.is_valid():
			extra = " " + str(_extra_cb.call())
		print("TEST_PERF_FRAME_MS avg=%.2f max=%.2f phys_avg=%.2f phys_max=%.2f eng_phys_ms=%.2f sim_avg=%.2f sim_hz=%.1f fps=%.0f units=%d nodes=%d draw_calls=%d mem_mb=%.0f rx_kbs=%.1f%s" % [
			frame_avg, _frame_max, phys_avg, _phys_max, eng_phys, sim_avg, sim_hz, fps, units, int(nodes), int(draw_calls), mem_mb, rx_kbs, extra
		])
	_phys_sum = 0.0
	_phys_max = 0.0
	_phys_n = 0
	_frame_sum = 0.0
	_frame_max = 0.0
	_frame_n = 0
	_sim_ms_sum = 0.0
	_sim_ms_max = 0.0
	_sim_n = 0
