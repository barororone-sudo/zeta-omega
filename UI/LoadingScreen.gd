@tool
extends Control

@onready var progress = $Panel/VBoxContainer/ProgressBar
@onready var label = $Panel/VBoxContainer/Label

func update_status(text: String, percent: float):
	if label: label.text = text
	if progress: progress.value = percent
