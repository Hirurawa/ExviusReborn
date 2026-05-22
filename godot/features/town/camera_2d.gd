extends Camera2D

# Camera settings
var zoom_min = Vector2(0.2, 0.2) # How far out you can zoom
var zoom_max = Vector2(2.0, 2.0) # How far in you can zoom
var zoom_speed = 0.1

var is_dragging = false

func _input(event):
	# Handle Mouse Dragging (Middle Click or Left Click)
	if event is InputEventMouseButton:
		# Change MOUSE_BUTTON_LEFT to MOUSE_BUTTON_MIDDLE if you prefer
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_dragging = event.is_pressed()
			
	# Handle Mouse Motion for panning
	if event is InputEventMouseMotion and is_dragging:
		# We divide by zoom so the mouse stays exactly synced with the ground
		position -= event.relative / zoom

	# Handle Zooming (Scroll Wheel)
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			# Zoom in
			zoom += Vector2(zoom_speed, zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Zoom out
			zoom -= Vector2(zoom_speed, zoom_speed)
			
		# Clamp the zoom so we don't zoom infinitely
		zoom = zoom.clamp(zoom_min, zoom_max)
