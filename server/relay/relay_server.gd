extends SceneTree
# 중계 서버 실행 진입점 (헤드리스):
#   ./Godot_v4.7.1-stable_win64.exe --headless --path . -s res://server/relay/relay_server.gd -- --port=9080

const RelayScript := preload("res://server/relay/relay.gd")

const DEFAULT_PORT := 9080


func _initialize() -> void:
	var port := DEFAULT_PORT
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
	var relay := RelayScript.new()
	relay.name = "Relay"
	root.add_child(relay)
	if relay.listen(port) != OK:
		quit(1)
