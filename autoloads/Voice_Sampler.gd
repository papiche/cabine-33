extends Node
# Voice_Sampler — capture 1s de voix, extrait une wavetable (1024 samples).
# Android/Desktop : bus "Capture" + AudioStreamMicrophone + AudioEffectRecord.
# Web     : JavaScriptBridge → navigator.mediaDevices.getUserMedia.
# Émet "wavetable_ready(wt: PackedFloat32Array)" quand prêt.

signal wavetable_ready(wt: PackedFloat32Array)
signal recording_started
signal recording_failed(reason: String)

const WT_SIZE     := 1024
const RECORD_S    := 1.0
const SAVE_PATH   := "user://voice_wavetable.dat"
const INST_SYNTH  := 0
const INST_VOICE  := 1

var my_wavetable: PackedFloat32Array = PackedFloat32Array()
var inst_id: int = INST_SYNTH

# ── Bus Capture (Android + Desktop) ────────────────────────────
var _rec_effect:  AudioEffectRecord  = null
var _mic_player:  AudioStreamPlayer  = null
var _rec_timer:   float = 0.0
var _recording:   bool  = false

func _ready():
	_load_from_disk()
	if not OS.has_feature("web"):
		_setup_capture_bus()

func _setup_capture_bus():
	# Réutiliser un AudioEffectRecord existant si présent
	for bus_i in range(AudioServer.bus_count):
		for fx_i in range(AudioServer.get_bus_effect_count(bus_i)):
			var fx = AudioServer.get_bus_effect(bus_i, fx_i)
			if fx is AudioEffectRecord:
				_rec_effect = fx
				print("🎙️ AudioEffectRecord trouvé sur bus '%s'" % AudioServer.get_bus_name(bus_i))
				_ensure_mic_player(AudioServer.get_bus_name(bus_i))
				return

	# Créer un bus "Capture" dédié, muet pour éviter le feedback
	var cap_idx := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(cap_idx, "Capture")
	AudioServer.set_bus_send(cap_idx, "")   # pas de routage vers Master
	AudioServer.set_bus_mute(cap_idx, true)

	_rec_effect = AudioEffectRecord.new()
	_rec_effect.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(cap_idx, _rec_effect)
	_ensure_mic_player("Capture")
	print("🎙️ Bus Capture créé avec AudioEffectRecord")

func _ensure_mic_player(bus_name: String):
	if is_instance_valid(_mic_player): return
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = bus_name
	add_child(_mic_player)

func _process(delta: float):
	if not _recording: return
	_rec_timer -= delta
	if _rec_timer <= 0.0:
		_recording = false
		if _rec_effect:
			_finish_native_record()

# ── Public API ─────────────────────────────────────────────────
func start_recording():
	if OS.has_feature("web"):
		_start_web()
	else:
		_start_native()

func get_inst_id() -> int:
	return inst_id

# ── Native (Android + Desktop) ─────────────────────────────────
func _start_native():
	if _rec_effect == null:
		_setup_capture_bus()
	if _rec_effect == null:
		emit_signal("recording_failed", "AudioEffectRecord indisponible")
		return
	if is_instance_valid(_mic_player) and not _mic_player.playing:
		_mic_player.play()
	_rec_effect.set_recording_active(true)
	_rec_timer = RECORD_S
	_recording = true
	emit_signal("recording_started")

func _finish_native_record():
	if is_instance_valid(_mic_player) and _mic_player.playing:
		_mic_player.stop()
	_rec_effect.set_recording_active(false)
	var clip: AudioStreamWAV = _rec_effect.get_recording()
	if clip == null:
		emit_signal("recording_failed", "Enregistrement vide — vérifiez la permission micro"); return
	var raw: PackedByteArray = clip.data
	if raw.is_empty():
		emit_signal("recording_failed", "Données micro vides — permission refusée ?"); return
	var pcm: PackedFloat32Array = _bytes_to_pcm(raw, clip.format)
	_extract_and_emit(pcm)

func _bytes_to_pcm(raw: PackedByteArray, fmt: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	match fmt:
		AudioStreamWAV.FORMAT_8_BITS:
			for b in raw: out.append((float(b) - 128.0) / 128.0)
		AudioStreamWAV.FORMAT_16_BITS:
			var i := 0
			while i + 1 < raw.size():
				var s := raw[i] | (raw[i+1] << 8)
				if s > 32767: s -= 65536
				out.append(float(s) / 32768.0)
				i += 2
		_:
			for _x in range(raw.size()): out.append(0.0)
	return out

# ── Web ────────────────────────────────────────────────────────
var _web_cb: JavaScriptObject = null

func _start_web():
	_web_cb = JavaScriptBridge.create_callback(_on_web_pcm_received)
	JavaScriptBridge.get_interface("window")["_a4lVoiceCb"] = _web_cb
	JavaScriptBridge.eval("""
(function() {
  navigator.mediaDevices.getUserMedia({audio: true, video: false})
  .then(function(stream) {
    var ctx = new AudioContext();
    var src = ctx.createMediaStreamSource(stream);
    var buf_size = Math.round(ctx.sampleRate * 1.05);
    var processor = ctx.createScriptProcessor(4096, 1, 1);
    var samples = [];
    processor.onaudioprocess = function(e) {
      var d = e.inputBuffer.getChannelData(0);
      for (var i = 0; i < d.length; i++) samples.push(d[i]);
      if (samples.length >= buf_size) {
        processor.disconnect(); src.disconnect();
        stream.getTracks().forEach(function(t){ t.stop(); });
        ctx.close();
        // Base64 Float32Array : 48k floats → ~192KB base64 (vs 800KB CSV), zéro parsing côté GDScript
        var slice = new Float32Array(samples.slice(0, buf_size));
        var u8 = new Uint8Array(slice.buffer);
        // String.fromCharCode.apply avec 200k args → Maximum call stack exceeded
        // Solution : découper en chunks de 8192 max
        var b64 = '';
        var u8a = new Uint8Array(u8);
        var chunk = 8192;
        for (var ci = 0; ci < u8a.length; ci += chunk) {
          b64 += String.fromCharCode.apply(null, u8a.subarray(ci, ci + chunk));
        }
        b64 = btoa(b64);
        if (window._a4lVoiceCb) window._a4lVoiceCb([b64]);
      }
    };
    src.connect(processor);
    processor.connect(ctx.destination);
  })
  .catch(function(e) {
    if (window._a4lVoiceCb) window._a4lVoiceCb(['ERROR:' + e.message]);
  });
})();
""")
	emit_signal("recording_started")

func _on_web_pcm_received(args: Array):
	if args.is_empty(): emit_signal("recording_failed", "Pas de données"); return
	var b64: String = str(args[0])
	if b64.begins_with("ERROR:"):
		emit_signal("recording_failed", b64.substr(6)); return
	# Décodage Base64 → bytes → Float32Array (ultra-rapide, zéro parsing de string)
	var raw_bytes := Marshalls.base64_to_raw(b64)
	if raw_bytes.is_empty(): emit_signal("recording_failed", "Décodage audio échoué"); return
	var pcm := raw_bytes.to_float32_array()
	_extract_and_emit(pcm)

# ── Extraction wavetable par zero-crossing ─────────────────────
func _extract_and_emit(pcm: PackedFloat32Array):
	if pcm.size() < WT_SIZE * 2:
		emit_signal("recording_failed", "Signal trop court (%d samples)" % pcm.size()); return

	var peak := 0.001
	for s in pcm: peak = maxf(peak, absf(s))
	var norm := PackedFloat32Array()
	for s in pcm: norm.append(s / peak)

	# ── LPF avant pitch detection : isoler la fondamentale ──────────────────
	# La voix brute contient des harmoniques aigus (formants) qui font "accrocher" le ZC
	# sur des micro-cycles de 10-20 samples → effet Chipmunk.
	# Solution : filtrer pour la DÉTECTION seulement (alpha≈0.15 ≈ coupure ~300Hz à 48kHz)
	# puis extraire le cycle depuis le signal ORIGINAL (norm) pour préserver le timbre.
	var lpf := PackedFloat32Array()
	lpf.resize(norm.size())
	var alpha := 0.15  # fréquence de coupure basse — isole la fondamentale vocale
	var prev  := 0.0
	for i in range(norm.size()):
		prev = alpha * norm[i] + (1.0 - alpha) * prev
		lpf[i] = prev

	# 1. Premier ZC montant sur le signal FILTRÉ (robuste aux harmoniques)
	var start := 512
	while start < lpf.size() - (WT_SIZE + 100):
		if lpf[start - 1] < 0.0 and lpf[start] >= 0.0: break
		start += 1

	# 2. Prochain ZC montant = fin d'un cycle fondamental
	# Minimum 60 samples (≈ 800 Hz max) pour ignorer les micro-passages à zéro du bruit
	var end_idx := start + 60
	while end_idx < lpf.size() - 2:
		if lpf[end_idx - 1] < 0.0 and lpf[end_idx] >= 0.0: break
		end_idx += 1

	var cycle_length := end_idx - start
	
	# Compensation du déphasage du filtre LPF
	# Retard théorique ≈ (1 - alpha) / alpha
	var phase_delay := int((1.0 - alpha) / alpha)
	var compensated_start := maxi(0, start - phase_delay)

	# 3. Ré-échantillonner le cycle (avec compensated_start)
	var wt := PackedFloat32Array()
	wt.resize(WT_SIZE)
	for i in range(WT_SIZE):
		var src_exact := compensated_start + (float(i) / float(WT_SIZE)) * float(cycle_length)
		var idx := int(src_exact)
		var frac := src_exact - float(idx)
		var s0 := norm[idx]     if idx     < norm.size() else 0.0
		var s1 := norm[idx + 1] if idx + 1 < norm.size() else 0.0
		wt[i] = lerpf(s0, s1, frac)
	# Pas besoin de fenêtrage de Hann : le cycle de ZC à ZC est déjà continu

	peak = 0.001
	for s in wt: peak = maxf(peak, absf(s))
	for i in range(WT_SIZE): wt[i] /= peak

	my_wavetable = wt
	inst_id = INST_VOICE
	_save_to_disk(wt)
	emit_signal("wavetable_ready", wt)

# ── Persistance ────────────────────────────────────────────────
func _save_to_disk(wt: PackedFloat32Array):
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null: return
	for v in wt: f.store_float(v)
	f.close()
	inst_id = INST_VOICE

func _load_from_disk():
	if not FileAccess.file_exists(SAVE_PATH): return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null: return
	var wt := PackedFloat32Array()
	while not f.eof_reached() and wt.size() < WT_SIZE:
		wt.append(f.get_float())
	f.close()
	if wt.size() == WT_SIZE:
		my_wavetable = wt
		inst_id = INST_VOICE

# ── Lecture wavetable ─────────────────────────────────────────
func read(phase: float) -> float:
	return read_wt(my_wavetable, phase)

func read_wt(wt: PackedFloat32Array, phase: float) -> float:
	if wt.is_empty(): return sin(phase)
	var exact: float = (phase / TAU) * float(wt.size())
	var i1: int = int(exact) % wt.size()
	var i2: int = (i1 + 1) % wt.size()
	var frac: float = exact - float(int(exact))
	return lerpf(wt[i1], wt[i2], frac)
