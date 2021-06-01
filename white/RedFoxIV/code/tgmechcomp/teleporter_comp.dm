//GLOBAL_LIST_INIT(mechcomp_teles,list())

/obj/item/mechcomp/teleport
	name = "mechcomp Teleporter"
	desc = "Teleports things around. This one is severly limited by range."
	part_icon_state = "comp_tele"
	active_icon_state = "comp_tele1"
	has_anchored_icon_state = TRUE
	//см. CONTRIBUTING.md, там описано, что такое static
	var/max_tele_range = 14
	var/tele_id
	var/target_id
	var/accept_mobs = FALSE
	var/static/list/obj/item/mechcomp/teleport/teles = list()



/obj/item/mechcomp/teleport/Initialize()
	. = ..()
	tele_id = (rand(0,65535))
	SEND_SIGNAL(src, COMSIG_MECHCOMP_ADD_INPUT, "Teleport!", "do_teleport")
	SEND_SIGNAL(src, COMSIG_MECHCOMP_ADD_INPUT, "Target ID", "set_target_id")
	SEND_SIGNAL(src, COMSIG_MECHCOMP_ADD_CONFIG, "Set teleporter's ID", "set_tele_id_manually")
	SEND_SIGNAL(src, COMSIG_MECHCOMP_ADD_CONFIG, "Set Target ID", "set_target_id_manually")
	SEND_SIGNAL(src, COMSIG_MECHCOMP_ADD_CONFIG, "Allow/Disallow living creatures", "toggle_accept_mobs")

/obj/item/mechcomp/teleport/examine(mob/user)
	. = ..()
	. += "<br>It's teleID is <font color='orange'>[num2hex(tele_id, 4)]</font> and it's current target teleID is <font color='orange'>[num2hex(target_id, 4)]</font>"


/obj/item/mechcomp/teleport/Destroy()
	. = ..()
	teles.Remove(src)


/obj/item/mechcomp/teleport/proc/do_teleport(datum/mechcompMessage/msg)
	if(!anchored || active || isnull(target_id))
		return

	var/obj/item/mechcomp/teleport/tele = teles?["[target_id]"]
	if(isnull(tele))
		say("Invalid target!")
		playsound(src, 'white/RedFoxIV/sounds/mechcomp/generic_energy_dryfire.ogg', 75, FALSE)
		activate_for(1 SECONDS, FALSE)
		return

	if((!isnull(max_tele_range) && get_dist(src,tele) > max_tele_range) || src.z != tele.z)
		say("Target out of range!")
		playsound(src, 'white/RedFoxIV/sounds/mechcomp/generic_energy_dryfire.ogg', 75, FALSE)
		activate_for(1 SECONDS, FALSE)
		return

	if(accept_mobs != tele.accept_mobs)
		say("Target and source modes differ - reconfigure teleporters!")
		playsound(src, 'white/RedFoxIV/sounds/mechcomp/generic_energy_dryfire.ogg', 75, FALSE)
		activate_for(1 SECONDS, FALSE)
		return

	var/list/thrown = list()
	var/mob/living/L
	for(var/atom/movable/AM in get_turf(src))
		if(AM.anchored || ( isliving(AM) && !accept_mobs ) || AM == src)
			continue
		AM.forceMove(get_turf(tele))
		if(isliving(AM))
			L = AM
			thrown.Add("[L.ckey] as [L.name]")
	
	playsound(src, 'sound/weapons/emitter2.ogg', 25, TRUE, extrarange = 3)
	playsound(tele, 'sound/weapons/emitter2.ogg', 25, TRUE, extrarange = 3)
	var/datum/effect_system/spark_spread/s1 = new(src)
	s1.set_up(rand(3,7), FALSE, src)
	s1.start()


	activate_for(1 SECONDS + 9 SECONDS * accept_mobs)
	tele.activate_for(1 SECONDS + 9 SECONDS * accept_mobs)
	log_action("teleported following people to x=[tele.x], y=[tele.y]: [jointext(thrown, ", ")]")
	return


/obj/item/mechcomp/teleport/activate_for(time, visual = TRUE)
	. = ..()
	flick("u[part_icon_state]_flick", src)


/obj/item/mechcomp/teleport/proc/set_target_id(datum/mechcompMessage/msg)
	var/id = text2num(msg.signal)
	if(!isnull(id) && id >=0 && id<=65535) //from 0 to FFFF
		if(teles["[id]"])
			return
		target_id = id 

/obj/item/mechcomp/teleport/proc/set_target_id_manually(obj/item/I, mob/user)
	var/input = hex2num(input("Enter new target teleID.", "Teleporter goin' up!", num2hex(target_id, 4)) as text|null)
	if(!in_range(src, user) || user.stat || isnull(input))
		return FALSE
	target_id = clamp(input, 0, 65535) //from 0 to FFFF
	to_chat(user, "<span class='notice'>You change the target ID on [src.name] to [num2hex(target_id, 4)].</span>")
	return TRUE


/obj/item/mechcomp/teleport/proc/set_tele_id_manually(obj/item/I, mob/user)
	var/input = hex2num(input("Enter new teleID.", "Teleporter goin' up!", num2hex(tele_id, 4)) as text|null)
	if(!in_range(src, user) || user.stat || isnull(input))
		return FALSE
	if(teles["[input]"])
		to_chat(user, "The [src.name] refuses the teleID! It seems there is already an another teleporter with the same teleID.")
		return FALSE
	teles.Remove("[tele_id]")
	tele_id = clamp(input, 0, 65535) //from 0 to FFFF
	teles += list("[tele_id]" = src)
	to_chat(user, "<span class='notice'>You change the tele ID on [src.name] to [num2hex(tele_id, 4)].</span>")
	return TRUE

/obj/item/mechcomp/teleport/proc/toggle_accept_mobs(obj/item/I, mob/user)
	accept_mobs = !accept_mobs
	if(accept_mobs)
		part_icon_state = "comp_tele_mob"
		active_icon_state = "comp_tele_mob1"
		update_icon_state(part_icon_state)
		to_chat(user, "The [src.name] will now teleport not only objects, but also living creatures. The increased power requirement will mean the teleporter takes longer to recharge, even if it did not teleport anything at all.")
	else
		part_icon_state = "comp_tele"
		active_icon_state = "comp_tele1"
		update_icon_state(part_icon_state)
		to_chat(user, "The [src.name] will no more teleport living creatures. The decreased power requirement means it will recharge faster.")

/obj/item/mechcomp/teleport/can_anchor(mob/user)
	.=..()
	if(teles["[tele_id]"])
		to_chat(user, "The [src.name] refuses to be anchored! It seems there is already an another teleporter with the same teleID.")
		return FALSE

/obj/item/mechcomp/teleport/can_unanchor(mob/user)
	. = ..()
	if(active)
		to_chat(user,"<span class='alert'>The [src.name] is still recharging and is locked in place!</span>")

/obj/item/mechcomp/teleport/anchor(mob/user)
	. = ..()
	teles += list("[tele_id]" = src)

/obj/item/mechcomp/teleport/unanchor(mob/user)
	. = ..()
	teles.Remove("[tele_id]")




/obj/item/mechcomp/teleport/longrange
	name = "mechcomp Long-Range Teleporter"
	desc = "Teleports things around. This one allows teleportations for much longer distances, althrough it's still not enough if you try to teleport off the station. <br><i>Interestingly enough, regular short-range teleports still can act like receivers for long-range ones.</i>"
	max_tele_range = null