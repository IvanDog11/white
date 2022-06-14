// 40mm (Grenade Launcher

/obj/projectile/bullet/a40mm
	name ="40mm граната"
	desc = "USE A WEEL GUN"
	icon_state= "bolter"
	damage = 60
	embedding = null
	shrapnel_type = null
	min_hitchance = 20

/obj/projectile/bullet/a40mm/on_hit(atom/target, blocked = FALSE)
	..()
	explosion(target, devastation_range = -1, light_impact_range = 2, flame_range = 3, flash_range = 1, adminlog = FALSE, explosion_cause = src)
	return BULLET_ACT_HIT
