// Boop Pebble case v2 — Waveshare ESP32-S3-Touch-AMOLED-1.64
//
// Sitting-blob enclosure: the buddy rests on a flat bottom and its flat
// face (screen + two buttons) tilts back so the screen looks up at you.
// Big boop dome on the crown, soft domed back.
//
// Board facts (research/eng/waveshare-amoled-port.md):
//   PCB 28.6 x 43.5 mm, 4x M2 holes at 22.86 x 38.50 mm spacing,
//   display active area 22.3 x 36.1 mm. Board mounts LANDSCAPE.
//   USB-C exits on the buddy's right (your left as you face it).
//
// World coordinates: buddy sits on z=0, +z up, face toward +y (viewer).
// Face-local coordinates (inside in_face()): face plane is z=0, +z out
// of the screen toward the viewer, +y up the face; interior is -z.
//
// Select what to generate:
//   part = "assembly" | "exploded" | "section" |
//          "front_shell" | "back_shell" | "boop_cap" | "face_cap"
part = "assembly";

$fn = 96;

/* ---------- MEASURE BEFORE TRUSTING (calipers!) ---------- */
display_stack = 2.5;  // glass+panel height above PCB front face
standoff_h    = 2.7;  // display_stack + 0.2 breathing room
board_thick   = 1.6;  // bare PCB thickness
usb_w         = 11.5; // USB-C slot width — generous until measured
usb_h         = 6.5;  // USB-C slot height — generous until measured
usb_z         = -7.75;// slot center depth — straddles PCB back face
screen_dx     = 0;    // active-area offset along board long axis. Likely
                      // NONZERO (FPC chin) — measure!

/* ---------- posture ---------- */
tilt   = 25;                // face tilt back from vertical, degrees
face_c = [0, 28, 30];       // world position of the face-facet center

/* ---------- body: a bao zi with a small face facet ---------- */
body_r   = 31;    // face-facet outer radius (small — the bun dominates)
rim_r    = 9;     // facet rim roundover
face_t   = 2.6;   // front wall thickness
cavity_r = 26.6;  // front cavity radius (board diagonal is 26.05)
z_split  = -15;   // shell parting plane (face-local)
bot_ring = 22;    // flat bottom: torus ring radius
bot_tube = 8;     //             torus tube radius
bun_c    = [0, -6, 34];        // bun ellipsoid center
bun_s    = [36, 29, 28];       // bun semi-axes (the whole body)
                  // bun front must stay behind the tilted face plane
                  // (grazes at -0.3 mm near z=45) or it bulges into the window
brow_c   = [0, 11.4, 45.4];    // brow sphere: the bao lip above the window
brow_r   = 10;                 // pokes ~1.5 mm past the face plane, local y 21

/* ---------- board ---------- */
board_w   = 43.5;
board_h   = 28.6;
hole_dx   = 38.50 / 2;
hole_dy   = 22.86 / 2;
screen_w  = 36.1 + 1.4;  // window opening = active area + margin
screen_h  = 22.3 + 1.4;
board_z   = -face_t - standoff_h;  // PCB front face (face-local)

/* ---------- buttons ---------- */
btn_x       = 8;      // face buttons at (+-btn_x, btn_y), face-local
btn_y       = -18.5;
btn_hole_d  = 8.6;
btn_head_d  = 8.2;
btn_flange_d= 11;
boop_hole_d = 13.4;
boop_head_d = 13.0;
boop_flange_d = 16.2;
cap_travel  = 1.2;
switch_body = 4.3;    // 6x6 tact switch body height
switch_plunger = 0.7;

/* ---------- fasteners ---------- */
boss_angles = [0, 135, 225];
boss_r      = 25.2;   // boss centers; merges into cavity wall
boss_d      = 6;
pilot_d     = 1.7;    // M2 self-tapping pilot

// face-local -> world (also mirrors X: buddy's right = world +X)
module in_face() {
    translate(face_c) rotate([-(90 - tilt), 0, 0]) rotate([0, 0, 180])
        children();
}
// world -> face-local, for print orientation
module deface() {
    rotate([0, 0, -180]) rotate([90 - tilt, 0, 0])
        translate([-face_c[0], -face_c[1], -face_c[2]]) children();
}

module rim_torus(ring, tube)
    rotate_extrude() translate([ring, 0]) circle(r = tube);

// flat tilted face, flat bottom, soft back bulge
module body() {
    hull() {
        in_face() translate([0, 0, -rim_r]) rim_torus(body_r - rim_r, rim_r);
        translate([0, 0, bot_tube]) rim_torus(bot_ring, bot_tube);
        translate(bun_c) scale([bun_s[0] / 29, 1, bun_s[2] / 29]) sphere(r = 29);
        translate(brow_c) sphere(r = brow_r);  // solid brow; no inner shell
    }
}

// cavity: known cylinder behind the face (board fit + lip registration)
// blending into a hollow belly
module interior() {
    hull() {
        in_face() translate([0, 0, -face_t]) cylinder(r = cavity_r, h = 0.1);
        in_face() translate([0, 0, -16]) cylinder(r = cavity_r, h = 0.1);
        translate([0, 0, face_t + bot_tube - 2.6])
            rim_torus(bot_ring, bot_tube - 2.6);
        translate(bun_c) scale([bun_s[0] / 29, 1, bun_s[2] / 29]) sphere(r = 26.4);
    }
}

module slab(z0, z1) translate([-70, -70, z0]) cube([140, 140, z1 - z0]);

module rounded_rect(w, h, r)
    offset(r = r) square([w - 2 * r, h - 2 * r], center = true);

// window with an outward chamfer for looks (face-local). The brow tents
// the hull ~1.5 mm proud of the facet plane, so the cuts reach well past
// z=0 to punch through the pillowed face cleanly.
module screen_window() translate([screen_dx, 0, 0]) {
    hull() {
        translate([0, 0, 2.5]) linear_extrude(0.1)
            offset(delta = 3.9) rounded_rect(screen_w, screen_h, 2.5);
        translate([0, 0, -1.4]) linear_extrude(0.1)
            rounded_rect(screen_w, screen_h, 2.5);
    }
    translate([0, 0, -face_t - 1]) linear_extrude(face_t + 6.5)
        rounded_rect(screen_w, screen_h, 2.5);
}

module usb_slot() {
    translate([-36, 0, usb_z]) rotate([0, 90, 0])
        linear_extrude(13) rounded_rect(usb_h, usb_w, 2);
}

module boop_axis() { translate([0, 0, -rim_r]) rotate([-90, 0, 0]) children(); }

/* ================= front shell (faceplate) ================= */
module front_shell() {
    difference() {
        union() {
            intersection() {
                difference() { body(); interior(); }
                in_face() slab(z_split, 5);
            }
            in_face() {
                // board standoffs (M2 self-tap from the back of the PCB)
                for (sx = [-1, 1], sy = [-1, 1])
                    translate([sx * hole_dx, sy * hole_dy, -face_t - standoff_h])
                        cylinder(d = 4.2, h = standoff_h + 0.1);
                // screw bosses, ribs merged into the cavity wall
                for (a = boss_angles) rotate([0, 0, a])
                    translate([boss_r, 0, z_split]) cylinder(d = boss_d, h = 7);
                // pad to glue the boop tact switch onto (switch faces +Y)
                translate([-5, 15.5, -13]) cube([10, 4, 10]);
            }
            // boop guide tube with flange shoulder, trimmed to the body
            intersection() {
                body();
                in_face() boop_axis() difference() {
                    translate([0, 0, 20]) cylinder(d = 18.5, h = 13);
                    translate([0, 0, 19.9]) cylinder(d = boop_flange_d + 0.6, h = 7.1);
                }
            }
        }
        in_face() {
            screen_window();
            usb_slot();
            // face button holes
            for (s = [-1, 1])
                translate([s * btn_x, btn_y, -face_t - 1])
                    cylinder(d = btn_hole_d, h = face_t + 6);
            // boop bore through the rim/crown
            boop_axis() translate([0, 0, 18]) cylinder(d = boop_hole_d, h = 25);
            // pilot holes for the shell screws
            for (a = boss_angles) rotate([0, 0, a])
                translate([boss_r, 0, z_split - 0.1]) cylinder(d = pilot_d, h = 7.6);
            // pilot holes in the standoffs
            for (sx = [-1, 1], sy = [-1, 1])
                translate([sx * hole_dx, sy * hole_dy, -face_t - standoff_h - 0.1])
                    cylinder(d = pilot_d, h = standoff_h + 1.6);
        }
    }
}

/* ================= back shell (body bowl) ================= */
module back_shell() {
    difference() {
        union() {
            intersection() {
                difference() { body(); interior(); }
                in_face() slab(-100, z_split);
            }
            // registration lip, notched around the front bosses
            in_face() difference() {
                translate([0, 0, z_split])
                    linear_extrude(2.4) difference() {
                        circle(r = cavity_r - 0.2);
                        circle(r = cavity_r - 1.95);
                    }
                for (a = boss_angles) rotate([0, 0, a])
                    translate([boss_r, 0, z_split - 1]) cylinder(d = boss_d + 1, h = 4.5);
            }
            // screw towers from the back wall up to the parting plane
            for (a = boss_angles) intersection() {
                body();
                in_face() rotate([0, 0, a])
                    translate([boss_r, 0, -60]) cylinder(d = 6.5, h = 60 + z_split);
            }
            // columns to glue the face-button tact switches onto
            for (s = [-1, 1]) intersection() {
                body();
                in_face() translate([s * btn_x, btn_y, -60]) cylinder(d = 9, h = 47);
            }
        }
        // screw channels: driver reaches through the back of the blob
        in_face() for (a = boss_angles) rotate([0, 0, a]) translate([boss_r, 0, 0]) {
            translate([0, 0, -70]) cylinder(d = 2.4, h = 55.2);   // to -14.8
            translate([0, 0, -70]) cylinder(d = 4.6, h = 53.5);   // head seat -16.5
        }
    }
}

/* ================= button caps ================= */
// face cap: head rides in the face hole, flange retains it behind the wall,
// stem reaches down to a tact switch glued on the back-shell column (top -13)
module face_cap() {
    cylinder(d = btn_head_d, h = face_t + 1.0);                    // head, ~1 mm proud
    translate([0, 0, -1.2]) cylinder(d = btn_flange_d, h = 1.3);   // flange
    stem_tip = -13 + switch_body + switch_plunger + 0.3;
    translate([0, 0, stem_tip + face_t + 1.2])
        cylinder(d = 3.6, h = -stem_tip - face_t - 1.2 + 0.1);
}

// boop cap along its own +Z axis; shoulder in the guide tube retains it
module boop_cap() {
    translate([0, 0, 27]) cylinder(d = boop_head_d, h = 9);         // head
    translate([0, 0, 36]) sphere(d = boop_head_d);                  // big dome top
    translate([0, 0, 27 - 1.3]) cylinder(d = boop_flange_d, h = 1.4);
    translate([0, 0, 20.2]) cylinder(d = 5.5, h = 7);               // switch pusher
}

/* ================= dummy board (visualization only) ================= */
module board_dummy() in_face() translate([0, 0, board_z]) {
    color("darkgreen") translate([0, 0, -board_thick])
        linear_extrude(board_thick) rounded_rect(board_w, board_h, 2);
    color("black") linear_extrude(display_stack - 0.1)
        rounded_rect(screen_w + 1, screen_h + 1, 1.5);
}

/* ================= scenes ================= */
module caps_in_place() {
    color("HotPink") in_face() boop_axis() boop_cap();
    color("LightSkyBlue") in_face()
        translate([btn_x, btn_y, -face_t - 1.0 + cap_travel]) face_cap();
    color("Salmon") in_face()
        translate([-btn_x, btn_y, -face_t - 1.0 + cap_travel]) face_cap();
}

// face normal, for exploded views
nrm = [0, cos(tilt), sin(tilt)];

if (part == "assembly") {
    color("MediumPurple") front_shell();
    color("RebeccaPurple") back_shell();
    caps_in_place();
    board_dummy();
} else if (part == "exploded") {
    translate(28 * nrm) { color("MediumPurple") front_shell(); }
    color("RebeccaPurple") back_shell();
    translate(50 * nrm) {
        color("HotPink") in_face() boop_axis() translate([0, 0, 10]) boop_cap();
        color("LightSkyBlue") in_face() translate([btn_x, btn_y, 12]) face_cap();
        color("Salmon") in_face() translate([-btn_x, btn_y, 12]) face_cap();
    }
    translate(14 * nrm) board_dummy();
} else if (part == "section") {
    difference() {
        union() {
            color("MediumPurple") front_shell();
            color("RebeccaPurple") back_shell();
            caps_in_place();
            board_dummy();
        }
        translate([0, -70, -10]) cube([80, 140, 90]);  // cut away +X half
    }
} else if (part == "shell_dbg") {
    // hollow body only, no unions/cuts except the window — for debugging
    rotate([180, 0, 0]) deface() difference() {
        body(); interior(); in_face() screen_window();
    }
} else if (part == "front_shell") {
    rotate([180, 0, 0]) deface() front_shell();          // face down on the bed
} else if (part == "back_shell") {
    rotate([180, 0, 0]) translate([0, 0, -z_split])
        deface() back_shell();                           // parting plane on the bed
} else if (part == "boop_cap") {
    translate([0, 0, -20.2]) boop_cap();                 // print WITH supports
} else if (part == "face_cap") {
    translate([0, 0, face_t + 1.0]) rotate([180, 0, 0]) face_cap(); // head down
}
