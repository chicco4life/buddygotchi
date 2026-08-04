// Boop Pebble case — Waveshare ESP32-S3-Touch-AMOLED-1.64
//
// Round "pebble" enclosure: flat face + domed back, boop button on top,
// screen window, menu/reject buttons below the screen.
//
// Board facts (research/eng/waveshare-amoled-port.md):
//   PCB 28.6 x 43.5 mm, 4x M2 holes at 22.86 x 38.50 mm spacing,
//   display active area 22.3 x 36.1 mm. Board mounts LANDSCAPE
//   (43.5 mm along X). USB-C exits on the LEFT (-X) side.
//
// Coordinates: face plane is z=0, interior is -z. +Y is up (boop side).
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
usb_w         = 11.5; // USB-C slot width (Y) — generous until measured
usb_h         = 6.5;  // USB-C slot height (Z) — generous until measured
usb_z         = -7.75;// slot center depth — straddles PCB back face
screen_dx     = 0;    // active-area offset along board long axis (X, toward
                      // +X = away from USB). Likely NONZERO (FPC chin) — measure!

/* ---------- body ---------- */
body_r   = 32;    // outer radius (64 mm wide)
rim_r    = 8;     // rim roundover
back_rxy = 29;    // back dome half-widths
back_rz  = 11;    // back dome half-depth
dome_cz  = -12;   // back dome center depth
face_t   = 2.6;   // front wall thickness
cavity_r = 27.5;  // main cavity radius (board diagonal is 26.05)
z_split  = -15;   // shell parting plane

/* ---------- board ---------- */
board_w   = 43.5;
board_h   = 28.6;
hole_dx   = 38.50 / 2;
hole_dy   = 22.86 / 2;
screen_w  = 36.1 + 1.4;  // window opening = active area + margin
screen_h  = 22.3 + 1.4;
board_z   = -face_t - standoff_h;  // PCB front face

/* ---------- buttons ---------- */
btn_x       = 8;      // face buttons at (+-btn_x, btn_y)
btn_y       = -19;
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

module ellipsoid(rxy, rz) { scale([1, 1, rz / rxy]) sphere(r = rxy); }

module rim_torus(ring, tube)
    rotate_extrude() translate([ring, 0]) circle(r = tube);

// flat face at z=0, rounded rim, domed back
module body() {
    hull() {
        translate([0, 0, -rim_r]) rim_torus(body_r - rim_r, rim_r);
        translate([0, 0, dome_cz]) ellipsoid(back_rxy, back_rz);
    }
}

// cavity: cylinder under the face blending into a smaller back dome
module interior() {
    hull() {
        translate([0, 0, -face_t]) cylinder(r = cavity_r, h = 0.1);
        translate([0, 0, z_split]) cylinder(r = cavity_r, h = 0.1);
        translate([0, 0, dome_cz]) ellipsoid(25.5, 7);
    }
}

module slab(z0, z1) translate([-60, -60, z0]) cube([120, 120, z1 - z0]);

module rounded_rect(w, h, r)
    offset(r = r) square([w - 2 * r, h - 2 * r], center = true);

// window with an outward chamfer for looks
module screen_window() translate([screen_dx, 0, 0]) {
    hull() {
        translate([0, 0, 0.5]) linear_extrude(0.1)
            offset(delta = 1.4) rounded_rect(screen_w, screen_h, 2.5);
        translate([0, 0, -1.4]) linear_extrude(0.1)
            rounded_rect(screen_w, screen_h, 2.5);
    }
    translate([0, 0, -face_t - 1]) linear_extrude(face_t + 1.5)
        rounded_rect(screen_w, screen_h, 2.5);
}

module usb_slot() {
    translate([-33, 0, usb_z]) rotate([0, 90, 0])
        linear_extrude(9) rounded_rect(usb_h, usb_w, 2);
}

module boop_axis() { translate([0, 0, -rim_r]) rotate([-90, 0, 0]) children(); }

/* ================= front shell ================= */
module front_shell() {
    difference() {
        union() {
            intersection() {
                difference() { body(); interior(); }
                slab(z_split, 1);
            }
            // board standoffs (M2 self-tap from the back of the PCB)
            for (sx = [-1, 1], sy = [-1, 1])
                translate([sx * hole_dx, sy * hole_dy, -face_t - standoff_h])
                    cylinder(d = 4.2, h = standoff_h + 0.1);
            // screw bosses, ribs merged into the cavity wall
            for (a = boss_angles) rotate([0, 0, a])
                translate([boss_r, 0, z_split]) cylinder(d = boss_d, h = 7);
            // boop guide tube with flange shoulder, trimmed to the body
            intersection() {
                body();
                boop_axis() difference() {
                    translate([0, 0, 20]) cylinder(d = 18.5, h = 13);
                    translate([0, 0, 19.9]) cylinder(d = boop_flange_d + 0.6, h = 7.1);
                }
            }
            // pad to glue the boop tact switch onto (switch faces +Y)
            translate([-5, 15.5, -13]) cube([10, 4, 10]);
        }
        screen_window();
        usb_slot();
        // face button holes
        for (s = [-1, 1])
            translate([s * btn_x, btn_y, -face_t - 1])
                cylinder(d = btn_hole_d, h = face_t + 2);
        // boop bore through the rim
        boop_axis() translate([0, 0, 18]) cylinder(d = boop_hole_d, h = 17);
        // pilot holes for the shell screws
        for (a = boss_angles) rotate([0, 0, a])
            translate([boss_r, 0, z_split - 0.1]) cylinder(d = pilot_d, h = 7.6);
        // pilot holes in the standoffs
        for (sx = [-1, 1], sy = [-1, 1])
            translate([sx * hole_dx, sy * hole_dy, -face_t - standoff_h - 0.1])
                cylinder(d = pilot_d, h = standoff_h + 1.6);
    }
}

/* ================= back shell ================= */
module back_shell() {
    difference() {
        union() {
            intersection() {
                difference() { body(); interior(); }
                slab(-30, z_split);
            }
            // registration lip, notched around the bosses
            difference() {
                translate([0, 0, z_split])
                    linear_extrude(2.4) difference() {
                        circle(r = cavity_r - 0.2);
                        circle(r = cavity_r - 1.95);
                    }
                for (a = boss_angles) rotate([0, 0, a])
                    translate([boss_r, 0, z_split - 1]) cylinder(d = boss_d + 1, h = 4.5);
            }
            // pads to glue the face-button tact switches onto
            for (s = [-1, 1])
                translate([s * btn_x, btn_y, -17.5]) cylinder(d = 9, h = 4.5);
        }
        // shell screw through-holes + head counterbores
        for (a = boss_angles) rotate([0, 0, a]) translate([boss_r, 0, 0]) {
            translate([0, 0, -22]) cylinder(d = 2.4, h = 8);
            translate([0, 0, -22]) cylinder(d = 4.6, h = 5.6);
        }
    }
}

/* ================= button caps ================= */
// face cap: head rides in the face hole, flange retains it behind the wall,
// stem reaches down to a tact switch glued on the back-shell pad
module face_cap() {
    cylinder(d = btn_head_d, h = face_t + 1.0);                    // head, ~1 mm proud
    translate([0, 0, -1.2]) cylinder(d = btn_flange_d, h = 1.3);   // flange
    stem_tip = -13 + switch_body + switch_plunger + 0.3;           // pad top is z=-13
    translate([0, 0, stem_tip + face_t + 1.2])
        cylinder(d = 3.6, h = -stem_tip - face_t - 1.2 + 0.1);
}

// boop cap along its own +Z axis; shoulder in the guide tube retains it
module boop_cap() {
    translate([0, 0, 27]) cylinder(d = boop_head_d, h = 5.5);       // head
    translate([0, 0, 32.5]) sphere(d = boop_head_d);                // big dome top
    translate([0, 0, 27 - 1.3]) cylinder(d = boop_flange_d, h = 1.4);
    translate([0, 0, 20.2]) cylinder(d = 5.5, h = 7);               // switch pusher
}

/* ================= dummy board (visualization only) ================= */
module board_dummy() {
    translate([0, 0, board_z]) {
        color("darkgreen") translate([0, 0, -board_thick])
            linear_extrude(board_thick) rounded_rect(board_w, board_h, 2);
        color("black") linear_extrude(display_stack - 0.1)
            rounded_rect(screen_w + 1, screen_h + 1, 1.5);
    }
}

/* ================= scenes ================= */
module caps_in_place() {
    color("HotPink") boop_axis() boop_cap();
    color("LightSkyBlue") translate([btn_x, btn_y, -face_t - 1.0 + cap_travel]) face_cap();
    color("Salmon") translate([-btn_x, btn_y, -face_t - 1.0 + cap_travel]) face_cap();
}

if (part == "assembly") {
    color("MediumPurple") front_shell();
    color("RebeccaPurple") back_shell();
    caps_in_place();
    board_dummy();
} else if (part == "exploded") {
    color("MediumPurple") front_shell();
    color("RebeccaPurple") translate([0, 0, -28]) back_shell();
    color("HotPink") boop_axis() translate([0, 0, 18]) boop_cap();
    color("LightSkyBlue") translate([btn_x, btn_y, 14]) face_cap();
    color("Salmon") translate([-btn_x, btn_y, 14]) face_cap();
    translate([0, 0, -14]) board_dummy();
} else if (part == "section") {
    difference() {
        union() {
            color("MediumPurple") front_shell();
            color("RebeccaPurple") back_shell();
            caps_in_place();
            board_dummy();
        }
        translate([0, -60, -35]) cube([70, 120, 45]);  // cut away +X half
    }
} else if (part == "front_shell") {
    rotate([180, 0, 0]) front_shell();       // face down on the bed
} else if (part == "back_shell") {
    translate([0, 0, -z_split]) back_shell(); // parting plane on the bed
} else if (part == "boop_cap") {
    translate([0, 0, -20.2]) boop_cap();       // pusher down — print WITH supports
} else if (part == "face_cap") {
    translate([0, 0, face_t + 1.0]) rotate([180, 0, 0]) face_cap(); // head down
}
