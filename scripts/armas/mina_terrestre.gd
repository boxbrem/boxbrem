extends Node2D
class_name MinaTerrestre
## Node2D com Sprite2D e Marker2D chamado pega, posicionado no ponto de contato da mão.
signal explodiu(posicao: Vector2)
signal liberou_mao(mina: Node2D)
signal mina_armada
const EfeitoExplosao = preload("res://scripts/armas/efeito_explosao_granada.gd")

@export_category("Inventário")
@export var nome_item: String = "Mina terrestre"
@export var tamanho_inventario: Vector2i = Vector2i.ONE
@export var icone_inventario: Texture2D
@export_range(4.0, 100.0) var raio_coleta: float = 24.0
@export_flags_2d_physics var mascara_player: int = 1

@export_category("Lançamento")
@export_range(50.0, 1500.0) var velocidade: float = 300.0
@export_range(20.0, 1000.0) var alcance_maximo: float = 150.0
@export_flags_2d_physics var mascara_impacto: int = 1

@export_category("Armadura e Detecção")
@export_range(0.1, 5.0) var tempo_armadura: float = 1.5
@export_range(4.0, 100.0) var raio_deteccao: float = 60.0
@export_flags_2d_physics var mascara_inimigos: int = 1

@export_category("Explosão")
@export_range(1, 500) var dano_maximo: int = 120
@export_range(8.0, 500.0) var raio_explosao: float = 100.0
@export_flags_2d_physics var mascara_dano: int = 1
@export_flags_2d_physics var mascara_paredes: int = 1
@export var dano_no_lancador: bool = false
@export var paredes_bloqueiam_dano: bool = true

@export_category("Mão")
@export var ponto_pega: Marker2D
@export var distancia_mao: float = 11.0
@export var deslocamento_mao: Vector2 = Vector2(0, 2)

@export_category("Física")
@export var gravidade: float = 650.0
@export var impulso_vertical: float = 100.0
@export_range(0.0, 0.9) var restituicao: float = 0.4
@export var atrito_chao: float = 300.0

var guardada: bool = false
var na_mao: bool = false
var lancada: bool = false
var esta_armada: bool = false
var detonada: bool = false
var tempo_armadura_restante: float = 0.0
var dono: Node2D
var lancador: Node2D
var area: Area2D
var area_deteccao: Area2D
var sprite: Sprite2D
var ignorados: Array[RID] = []
var escala_no_mapa: Vector2 = Vector2.ONE
var sprite_posicao: Vector2
var sprite_rotacao: float = 0.0
var velocidade_plana: Vector2 = Vector2.ZERO
var altura: float = 0.0
var velocidade_vertical: float = 0.0
var z_mao_original: int = 0
var mao_visual: Node2D
var origem_lancamento: Vector2
var conferir_saida: bool = false
var inimigos_detectados: Array[Node2D] = []

func _ready() -> void:
	process_priority = 20
	sprite = get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite_posicao = sprite.position
		sprite_rotacao = sprite.rotation
		if icone_inventario == null:
			icone_inventario = sprite.texture
	if ponto_pega == null:
		ponto_pega = get_node_or_null("pega") as Marker2D
	if ponto_pega == null:
		for filho in find_children("*", "Marker2D", true, false):
			ponto_pega = filho as Marker2D
			break
	escala_no_mapa = global_scale
	add_to_group("minas_coletaveis")
	
	# Area de coleta
	area = Area2D.new()
	area.name = "AlcanceColeta"
	area.collision_layer = 0
	area.collision_mask = mascara_player
	area.monitorable = false
	var colisao := CollisionShape2D.new()
	var forma := CircleShape2D.new()
	forma.radius = raio_coleta
	colisao.shape = forma
	area.add_child(colisao)
	area.body_entered.connect(_entrou)
	area.body_exited.connect(_saiu)
	add_child(area)
	
	# Area de detecção de inimigos
	area_deteccao = Area2D.new()
	area_deteccao.name = "DeteccaoInimigos"
	area_deteccao.collision_layer = 0
	area_deteccao.collision_mask = mascara_inimigos
	area_deteccao.monitorable = false
	var colisao_deteccao := CollisionShape2D.new()
	var forma_deteccao := CircleShape2D.new()
	forma_deteccao.radius = raio_deteccao
	colisao_deteccao.shape = forma_deteccao
	area_deteccao.add_child(colisao_deteccao)
	area_deteccao.body_entered.connect(_inimigo_entrou)
	area_deteccao.body_exited.connect(_inimigo_saiu)
	area_deteccao.monitoring = false
	add_child(area_deteccao)

func get_slot_equipamento() -> StringName:
	return &"extra"

func pode_ser_coletada() -> bool:
	return not guardada and not na_mao and not lancada and not esta_armada and not detonada

func _entrou(corpo: Node2D) -> void:
	if pode_ser_coletada() and corpo.has_method("registrar_arma_proxima"):
		corpo.call("registrar_arma_proxima", self)

func _saiu(corpo: Node2D) -> void:
	if is_instance_valid(corpo) and corpo.has_method("remover_arma_proxima"):
		corpo.call("remover_arma_proxima", self)

func _desativar_coleta() -> void:
	if is_instance_valid(area):
		if area.monitoring:
			for corpo in area.get_overlapping_bodies():
				_saiu(corpo)
		area.set_deferred("monitoring", false)

func _inimigo_entrou(corpo: Node2D) -> void:
	if esta_armada and not detonada and corpo != lancador:
		if inimigos_detectados.find(corpo) == -1:
			inimigos_detectados.append(corpo)
			_explodir()

func _inimigo_saiu(corpo: Node2D) -> void:
	var indice = inimigos_detectados.find(corpo)
	if indice != -1:
		inimigos_detectados.remove_at(indice)

func guardar(novo_dono: Node2D, deposito: Node2D) -> bool:
	if not pode_ser_coletada() or not is_instance_valid(novo_dono) or not is_instance_valid(deposito):
		return false
	_desativar_coleta()
	guardada = true
	dono = novo_dono
	reparent(deposito)
	hide()
	return true

func pode_empunhar() -> bool:
	if not is_instance_valid(ponto_pega):
		push_warning("Mina: adicione o Marker2D pega no ponto de contato da mão.")
		return false
	return guardada and not na_mao and not esta_armada and not detonada

func empunhar(jogador: Node2D) -> bool:
	if not pode_empunhar() or jogador != dono or not jogador.has_method("fixar_m1"):
		return false
	na_mao = true
	lancador = jogador
	mao_visual = jogador.get("m1") as Node2D
	if is_instance_valid(mao_visual):
		z_mao_original = mao_visual.z_index
	reparent(jogador.get_parent())
	global_scale = escala_no_mapa
	show()
	jogador.call("fixar_m1", ponto_pega)
	_atualizar_na_mao()
	return true

func recolher(deposito: Node2D) -> bool:
	if not na_mao or esta_armada or not is_instance_valid(deposito):
		return false
	_soltar_mao_visual()
	na_mao = false
	reparent(deposito)
	hide()
	return true

func _soltar_mao_visual() -> void:
	if is_instance_valid(lancador) and lancador.has_method("soltar_m1"):
		lancador.call("soltar_m1")
	if is_instance_valid(mao_visual):
		mao_visual.z_index = z_mao_original
	mao_visual = null

func _atualizar_na_mao() -> void:
	if not is_instance_valid(lancador) or not is_instance_valid(ponto_pega):
		return
	var vetor: Vector2 = lancador.get_global_mouse_position() - lancador.global_position
	var direcao: Vector2 = vetor.normalized() if vetor.length_squared() > 0.01 else Vector2.DOWN
	if not bool(lancador.get("recebendo_dano")):
		if lancador.has_method("_atualizar_direcao_olhar"):
			lancador.call("_atualizar_direcao_olhar", direcao)
		if lancador is CharacterBody2D and lancador.has_method("_tocar_animacao"):
			var acao: String = "walk" if (lancador as CharacterBody2D).velocity.length_squared() > 0.01 else "idle"
			lancador.call("_tocar_animacao", acao)
	global_rotation = direcao.angle()
	global_position = lancador.global_position
	var alvo_mao: Vector2 = lancador.global_position + direcao * distancia_mao + deslocamento_mao
	global_position += alvo_mao - ponto_pega.global_position
	z_index = lancador.z_index + (2 if direcao.y >= 0 else -1)
	if is_instance_valid(mao_visual):
		mao_visual.z_index = 4 if direcao.y >= 0 else -1
	if lancador.has_method("_atualizar_maos"):
		lancador.call("_atualizar_maos", 0.0)

func lancar(jogador: Node2D, alvo: Vector2) -> bool:
	if not na_mao or esta_armada or detonada or jogador != lancador:
		return false
	var vetor: Vector2 = alvo - global_position
	var direcao: Vector2 = vetor.normalized() if vetor.length_squared() > 0.01 else Vector2.DOWN
	var alcance: float = clampf(vetor.length(), 25.0, maxf(alcance_maximo, 25.0))
	
	# Voo balístico virtual: o plano do mapa não depende do deslocamento visual vertical.
	velocidade_vertical = maxf(impulso_vertical, 1.0)
	altura = 5.0
	var duracao_voo: float = (velocidade_vertical + sqrt(velocidade_vertical * velocidade_vertical + 2.0 * maxf(gravidade, 1.0) * altura)) / maxf(gravidade, 1.0)
	velocidade_plana = direcao * minf(maxf(velocidade, 1.0), alcance / maxf(duracao_voo, 0.1))
	origem_lancamento = jogador.global_position
	conferir_saida = true
	_liberar_para_voo()
	return true

func _liberar_para_voo() -> void:
	_soltar_mao_visual()
	na_mao = false
	guardada = false
	lancada = true
	dono = null
	ignorados.clear()
	if is_instance_valid(lancador):
		_coletar_rids(lancador, ignorados)
	global_rotation = 0.0
	liberou_mao.emit(self)

func dropar(novo_pai: Node, posicao_no_mundo: Vector2) -> bool:
	if not guardada or na_mao or esta_armada or detonada or not is_instance_valid(novo_pai):
		return false
	guardada = false
	dono = null
	reparent(novo_pai)
	global_position = posicao_no_mundo
	global_rotation = 0.0
	global_scale = escala_no_mapa
	show()
	area.set_deferred("monitoring", true)
	return true

func _physics_process(delta: float) -> void:
	if detonada:
		return
	
	if na_mao:
		if not is_instance_valid(lancador) or bool(lancador.get("morto")):
			_soltar_mao_visual()
			na_mao = false
			guardada = false
			dono = null
			area.set_deferred("monitoring", true)
			liberou_mao.emit(self)
		else:
			_atualizar_na_mao()
	
	# Período de armadura
	if esta_armada and tempo_armadura_restante > 0.0:
		tempo_armadura_restante -= delta
		if tempo_armadura_restante <= 0.0:
			# Mina foi armada e passou pelo tempo de armadura
			pass
	
	if not lancada:
		return
	
	if conferir_saida:
		conferir_saida = false
		var saida := PhysicsRayQueryParameters2D.create(origem_lancamento, global_position, mascara_impacto, ignorados)
		saida.hit_from_inside = true
		var bloqueio: Dictionary = get_world_2d().direct_space_state.intersect_ray(saida)
		if not bloqueio.is_empty():
			global_position = Vector2(bloqueio["position"]) + Vector2(bloqueio["normal"]) * 1.5
			velocidade_plana = Vector2.ZERO
			_armar_mina()
			return
	
	var destino: Vector2 = global_position + velocidade_plana * delta
	if velocidade_plana.length_squared() > 0.1:
		var consulta := PhysicsRayQueryParameters2D.create(global_position, destino, mascara_impacto, ignorados)
		consulta.hit_from_inside = true
		var contato: Dictionary = get_world_2d().direct_space_state.intersect_ray(consulta)
		if not contato.is_empty():
			var normal: Vector2 = contato["normal"]
			global_position = Vector2(contato["position"]) + normal * 1.5
			velocidade_plana = velocidade_plana.bounce(normal) * 0.48 if not normal.is_zero_approx() else Vector2.ZERO
		else:
			global_position = destino
	
	if altura > 0.0 or velocidade_vertical > 0.0:
		velocidade_vertical -= maxf(gravidade, 1.0) * delta
		altura += velocidade_vertical * delta
		if altura <= 0.0:
			altura = 0.0
			velocidade_vertical = -velocidade_vertical * restituicao
			velocidade_plana *= 0.66
			if velocidade_vertical < 18.0:
				velocidade_vertical = 0.0
				# Mina pousou no chão, arma a mina
				_armar_mina()
	else:
		velocidade_plana = velocidade_plana.move_toward(Vector2.ZERO, atrito_chao * delta)
	
	if sprite != null:
		sprite.position = sprite_posicao + Vector2(0.0, -altura / maxf(absf(global_scale.y), 0.01))
	
	queue_redraw()

func _armar_mina() -> void:
	if esta_armada or detonada or not lancada:
		return
	lancada = false
	esta_armada = true
	tempo_armadura_restante = tempo_armadura
	area_deteccao.set_deferred("monitoring", true)
	mina_armada.emit()
	if sprite != null and sprite.is_connected("animation_finished", Callable()):
		# Pode adicionar animação de armadura aqui se necessário
		pass

func _draw() -> void:
	if not lancada or detonada:
		return
	var fator: float = clampf(1.0 - altura / 120.0, 0.35, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 4.5 * fator, Color(0, 0, 0, 0.32 * fator))
	draw_set_transform(Vector2.ZERO)

func _coletar_rids(no: Node, lista: Array[RID]) -> void:
	if no is CollisionObject2D:
		lista.append((no as CollisionObject2D).get_rid())
	for filho in no.get_children():
		_coletar_rids(filho, lista)

func _alvo_de_dano(no: Node) -> Node2D:
	var atual: Node = no
	while is_instance_valid(atual):
		if atual is Node2D and atual.has_method("receber_dano"):
			return atual as Node2D
		atual = atual.get_parent()
	return null

func _explodir() -> void:
	if detonada:
		return
	detonada = true
	esta_armada = false
	lancada = false
	area_deteccao.set_deferred("monitoring", false)
	if is_instance_valid(sprite):
		sprite.hide()
	global_scale = Vector2.ONE
	global_rotation = 0.0
	var forma := CircleShape2D.new()
	forma.radius = maxf(raio_explosao, 1.0)
	var consulta := PhysicsShapeQueryParameters2D.new()
	consulta.shape = forma
	consulta.transform = Transform2D(0.0, global_position)
	consulta.collision_mask = mascara_dano
	consulta.collide_with_bodies = true
	consulta.collide_with_areas = true
	var alvos: Dictionary = {}
	for resultado in get_world_2d().direct_space_state.intersect_shape(consulta, 256):
		var alvo: Node2D = _alvo_de_dano(resultado["collider"] as Node)
		if not is_instance_valid(alvo) or (alvo == lancador and not dano_no_lancador):
			continue
		alvos[alvo] = true
	for chave in alvos:
		if not is_instance_valid(chave):
			continue
		var alvo: Node2D = chave as Node2D
		var distancia: float = global_position.distance_to(alvo.global_position)
		if paredes_bloqueiam_dano and distancia > 1.0:
			var excecoes: Array[RID] = []
			_coletar_rids(alvo, excecoes)
			var raio := PhysicsRayQueryParameters2D.create(global_position, alvo.global_position, mascara_paredes, excecoes)
			raio.hit_from_inside = true
			if not get_world_2d().direct_space_state.intersect_ray(raio).is_empty():
				continue
		var fator: float = lerpf(1.0, 0.25, clampf(distancia / maxf(raio_explosao, 1.0), 0.0, 1.0))
		alvo.call("receber_dano", maxi(1, roundi(float(dano_maximo) * fator)))
	var efeito = EfeitoExplosao.new()
	efeito.raio = raio_explosao
	get_parent().add_child(efeito)
	efeito.global_position = global_position
	efeito.z_index = z_index + 2
	explodiu.emit(global_position)
	queue_free()
