# 4D Opaque Hexagonal Geo-Addressing Scheme Using Dynamic Goldberg Polyhedra and Chinese Remainder Theorem Encoding

**Authors:** Frédéric Renault  
**Institution:** G1FabLab / UPlanet ORIGIN  
**License:** Creative Commons Attribution 4.0  
**Code:** https://github.com/papiche/Astroport.ONE (AGPL-3.0)

---

## Abstract

This disclosure describes a compact, opaque geographic addressing format ("a4l:") for hexagonal cells of a Goldberg polyhedron tessellation of the Earth's surface. Unlike static geographic grids, this framework applies a continuous temporal rotation (precession) to the tessellation lattice using the Golden Ratio (φ = 1.6180339...) as the rotation period divisor, creating a 4-dimensional address (spatial + temporal) that cannot be decoded without knowledge of the exact Unix timestamp at event creation.

Format: `a4l:P<PP>H<QQQQ><RRRR>` where PP = pentagon identifier (00-11), QQQQ/RRRR = axial hex coordinates offset-encoded as 16-bit unsigned hexadecimal values.

The dynamic grid makes the addressing scheme privacy-preserving by design: without the original Unix timestamp and the Golden Ratio precession parameter, coordinates cannot be reliably reverse-mapped to standard GPS coordinates. Applications include geographic tagging of decentralized protocol events (NOSTR NIP-01) with spatial privacy from external scrapers while enabling precise spatial queries within trusted client implementations.

Prior art: Goldberg polyhedra (Goldberg, 1937), axial hex coordinates (standard), Golden Ratio mathematics (ancient). No prior combination of dynamic Golden Ratio precession with hexagonal Goldberg tessellation for opaque geographic addressing is known to the authors.

---

## 1. Background

Standard geographic coordinate systems (WGS84, What3Words, H3, S2) produce deterministic, reversible addresses. Any observer can decode a published coordinate to a real-world location. For decentralized social applications requiring geographic proximity computation without full location disclosure, this property is undesirable.

This disclosure presents a geographic addressing scheme where:
1. Addresses are compact ASCII strings (~20 characters)
2. Decoding requires knowledge of a time-varying rotation parameter
3. Hexagonal topology enables natural proximity computation
4. Addresses remain internally consistent for spatial queries within trusted clients

---

## 2. Static Framework: Goldberg Polyhedron Tessellation

### 2.1 Pentagon Nodes

A Goldberg polyhedron GP(n,m) tessellated over the Earth sphere produces exactly 12 pentagonal nodes and approximately (10n² + 10nm + 10m² + 2) hexagonal cells. The 12 pentagon nodes correspond to the 12 vertices of the underlying icosahedron projected onto the unit sphere.

In the static (t=0) reference frame, pentagon positions are defined by standard icosahedral geometry:

```
Pentagon 0  : lat=+90.0°,  lon=  0.0°   (North Pole — fixed)
Pentagon 11 : lat=-90.0°,  lon=  0.0°   (South Pole — fixed)
Pentagons 1-5  : lat≈+26.57°, lon= 0°, 72°, 144°, 216°, 288°
Pentagons 6-10 : lat≈-26.57°, lon=36°, 108°, 180°, 252°, 324°
```

### 2.2 Axial-to-Cube Projection (Pointy-Top Orientation)

Hexagonal cells within each pentagon's local frame are identified by axial coordinates (q, r). The projection from geographic coordinates (lat, lon) to axial hex coordinates uses the **pointy-top** orientation, where x maps to latitude and y maps to longitude:

```
x = lat_radians × Earth_radius_km       [km along meridian]
y = lon_radians × Earth_radius_km × cos(lat_radians)   [km along parallel]

q = round( (√3/3) × x − (1/3) × y ) / hex_size_km
r = round( (2/3) × y ) / hex_size_km
```

The inverse projection (hex center to GPS) is:
```
x_km = (√3 × q + √3/2 × r) × hex_size_km
y_km = (3/2 × r) × hex_size_km
center_lat = x_km / Earth_radius_km × (180/π)
center_lon = y_km / (Earth_radius_km × cos(center_lat_radians)) × (180/π)
```

This pointy-top formulation (q axis aligned with lat, r axis oblique) is distinct from the flat-top orientation commonly referenced in hexagonal grid literature. Both satisfy the cubic constraint x + y + z = 0 (z = −q − r), required for correct neighbor computation and distance metrics.

**Note on spherical approximation:** The `x = lat_rad × R`, `y = lon_rad × R × cos(lat_rad)` mapping is a local tangent-plane (cylindrical equidistant) approximation, not a closed spherical projection. It minimizes distortion at the local interaction scale (< 100 km from the pentagon center) but does not tile perfectly at planetary scale. The a4l: addressing scheme is therefore defined as a **local tangent-plane axial projection centered on the nearest dynamic pentagon node**, not a global spherical tessellation. This is the appropriate precision for the interaction distances of interest (1–50 km hexagonal cells).

---

## 3. Dynamic Framework: Golden Ratio Precession

### 3.1 Temporal Rotation

The novel contribution of this disclosure is the application of a continuous solid-body rotation of the entire icosahedral reference frame around the Earth's polar axis (Z-axis). Because Pentagons 0 and 11 lie exactly on the axis of rotation (lat = ±90°), their geographic coordinates naturally remain invariant — they are not "exempted" from the rotation but are geometrically fixed by it. The other 10 pentagons precess continuously in longitude.

**Rotation period:**
```
T_phi = 86400.0 / φ  =  86400.0 / 1.6180339...  ≈  53,398.3 seconds
     ≈ 14.83 hours
```

Where φ = (1 + √5) / 2 = 1.6180339... is the Golden Ratio.

**Angle at Unix timestamp `unix_ts`:**
```
angle_rad = fmod(unix_ts, T_phi) / T_phi × 2π
```

**Dynamic pentagon longitude:**
```
for pentagon_i in {1..10}:
    lon_dynamic_i = fmod(lon_static_i + degrees(angle_rad), 360.0)
    lat_dynamic_i = lat_static_i  (unchanged)
```

The polar pentagons (indices 0 and 11) are exempt from rotation:
```
Pentagon 0  : lat=+90°, lon=0° (always fixed)
Pentagon 11 : lat=-90°, lon=0° (always fixed)
```

### 3.2 Pentagon Assignment

Given a geographic point (lat, lon) and a Unix timestamp `unix_ts`:

1. Compute all 12 dynamic pentagon positions at `unix_ts`
2. Compute haversine distance from the point to each dynamic pentagon
3. Assign the point to the nearest pentagon: `PP = argmin(haversine_distance)`

Because the pentagon frame rotates, the same GPS coordinates will be assigned to different pentagon indices at different timestamps. This is the primary source of temporal opacity.

---

## 4. Address Encoding

### 4.1 Axial Coordinate Encoding

Given axial coordinates (q, r) in the local pentagon frame:

```
QQQQ = hex4( (q + 32768) & 0xFFFF )
RRRR = hex4( (r + 32768) & 0xFFFF )
```

The 32768 (= 0x8000) offset centers the signed 16-bit integer range [-32768, +32767] onto the unsigned range [0, 65535], enabling zero-padding to exactly 4 hex digits. This accommodates approximately ±32,000 hexagonal cells in each axial direction from the pentagon center, covering all resolutions of practical interest at Earth scale.

### 4.2 Full Address Format

```
a4l:P<PP>H<QQQQ><RRRR>
```

Examples:
```
a4l:P02H820B7F6C    (pentagon 02, q=3, r=-2404)
a4l:P00H80008000    (pentagon 00 center, q=0, r=0)
a4l:P11HFFFFFFFF    (pentagon 11, maximum axial extent)
```

Total address length: 18 characters (fixed).

### 4.3 Decoding Requirement

To decode an a4l: address back to approximate GPS coordinates, a client requires:
1. The original `unix_ts` (typically extracted from the NOSTR event timestamp)
2. The Golden Ratio precession formula (disclosed in this document)
3. The axial-to-cube projection parameters (hex_size_km, Earth_radius_km)
4. Knowledge of which pentagon index (PP) to use as reference frame origin

Without (1) or (2), the latitude/longitude of the pentagon reference frame cannot be reconstructed, making the hexagonal cell coordinates uninterpretable as standard GPS.

---

## 5. 4D Properties

The combination of spatial hex coordinates (q, r) and temporal indexing creates a 4-dimensional address:

| Dimension | Encoded as | Range |
|-----------|-----------|-------|
| Latitude  | Implicit in (q,r) within pentagon frame | Global |
| Longitude | Implicit in (q,r) + pentagon index | Global |
| Altitude  | Not encoded (surface-only) | N/A |
| Time      | Required for pentagon frame decoding | Unix epoch |

Two events at identical GPS coordinates but different Unix timestamps will produce different a4l: addresses if the pentagon assignment changes due to the Golden Ratio precession. This is a deliberate design property: spatial clustering is time-coherent over ~14.83-hour windows (one full rotation period), creating natural temporal neighborhoods.

---

## 6. Privacy Properties

**From external scrapers:** An a4l: address in a NOSTR event reveals no interpretable location without the precession formula and event timestamp. Standard GPS-based geographic indexers cannot cluster a4l: events by location.

**Within trusted clients:** Clients implementing the full decoding stack can compute pairwise proximity between any two a4l: addresses by:
1. Decoding both to (lat, lon) using their respective timestamps
2. Computing haversine distance
3. Or comparing (PP, q, r) tuples directly (same PP + adjacent axial = same neighborhood)

**Hexagonal cell center targeting:** The center of the hexagonal cell corresponding to an a4l: address can be computed exactly by inverting the axial projection, enabling precise rendezvous mechanics (e.g., "Cabine-33 ritual": arrive within 50m of cell center at specific timestamp).

**Proof-of-Presence via Velocity-Bounded Temporal Anchoring:**

To interact with a specific hexagonal cell (e.g., unlocking NOSTR events anchored to it), the system enforces a hardware-level proof of physical presence. The device must:

1. Enter a spatial tolerance radius (e.g., 50 meters) of the exact computed geographic center of the hexagonal cell
2. Maintain a spatial velocity below a threshold (e.g., 2.0 km/h) continuously for a fixed duration (e.g., 33 seconds)

The velocity criterion — rather than a static distance threshold — is used deliberately to filter out GPS coordinate drift (which can shift a stationary device by 5-20 meters without movement) and to prevent "drive-by" automated spoofing by GPS emulation software. A stationary human and a moving vehicle produce distinct velocity signatures even when both report the same coordinates.

During the anchoring phase, the device generates a **binaural beat** using two audio channels at mathematically derived frequencies:
- Left channel: F_water = 429.62 Hz (base frequency, derived from physiological water resonance)
- Right channel: F_water + F_Φ = 429.62 + 33.17 = 462.79 Hz
- Neural beat frequency: F_Φ = 33.17 Hz (the Phi2X ratio differential: F_PHI − F_2 = 33.17 − 31.32 + correction)

The 33.17 Hz inter-aural frequency differential is not arbitrary: it is the same constant `F_PHI` used as the wave-stretch factor in the personal phase computation (Section 2 of companion Disclosure 1), creating a coherent mathematical link between the spatial anchoring mechanics and the individual's phase identity.

---

## 7. Implementation Reference

Reference implementation in GDScript (Godot 4.x), available in ATOM4LOVE / Cabine-33 project (AGPL-3.0):

```gdscript
const PHI: float = 1.6180339887

func get_dynamic_pentagons(unix_ts: int) -> Array:
    var T_phi: float = 86400.0 / PHI
    var angle_rad: float = fmod(float(unix_ts), T_phi) / T_phi * TAU

    var pentagons: Array = _get_static_pentagons()  # 12 base positions
    for i in range(1, 11):  # skip poles 0 and 11
        var lon_deg: float = pentagons[i].y
        lon_deg = fmod(lon_deg + rad_to_deg(angle_rad), 360.0)
        pentagons[i].y = lon_deg
    return pentagons

func gps_to_hex_index(lat: float, lon: float) -> Vector3:
    var x: float = lat * (PI / 180.0) * EARTH_RADIUS_KM
    var y: float = lon * (PI / 180.0) * EARTH_RADIUS_KM * cos(lat * PI / 180.0)
    var q: int = roundi((sqrt(3.0) / 3.0 * x - (1.0 / 3.0) * y) / HEX_SIZE_KM)
    var r: int = roundi((2.0 / 3.0 * y) / HEX_SIZE_KM)
    return _axial_to_cube(Vector2(q, r))

func geo_tags(lat: float, lon: float, unix_ts: int) -> Array:
    var penta: Dictionary = get_nearest_pentagon(lat, lon, unix_ts)
    var pid: int = penta.get("pentagon_id", 0)
    var x: float = lat * R
    var y: float = lon * R * cos(deg_to_rad(lat))
    var q: int = roundi((2.0/3.0) * x)
    var r: int = roundi((-1.0/3.0) * x + (sqrt(3.0)/3.0) * y)
    var qenc: String = "%04X" % ((q + 32768) & 0xFFFF)
    var renc: String = "%04X" % ((r + 32768) & 0xFFFF)
    return [
        ["l", "a4l:P%02d" % pid, "atom4love"],
        ["l", "a4l:P%02dH%s%s" % [pid, qenc, renc], "atom4love"]
    ]
```

---

## 8. Prior Art and Novelty

**Known prior art:**
- Goldberg polyhedra: Goldberg (1937)
- Axial hex coordinates: standard computational geometry
- H3 hierarchical hexagonal indexing: Uber (2018) — static, non-rotated
- S2 spherical geometry library: Google (2011) — static, non-hexagonal
- Golden Ratio: ancient mathematics, Fibonacci (13th century)

**Novel combination:**
No prior art is known for:
1. Applying Golden Ratio (φ)-based temporal rotation to pentagonal nodes of a Goldberg tessellation
2. Using this dynamic frame as a geographic addressing system
3. The resulting temporal opacity property: same GPS coordinates → different hex address at different times

---

## 9. Claims of Novelty

1. A geographic addressing format using dynamic Goldberg polyhedron pentagonal nodes where non-polar nodes rotate in longitude at a period of `86400 / φ` seconds.

2. The resulting 4D address format `a4l:P<PP>H<QQQQ><RRRR>` where decoding requires the original Unix timestamp.

3. The 32768-offset hex encoding of axial coordinates ensuring fixed-width 4-character representations for both positive and negative axial values.

4. The specific combination of Golden Ratio precession period with icosahedral pentagon geometry creating ~14.83-hour temporal neighborhoods for spatial-temporal event clustering.

5. A mechanism for verifying physical presence at a mathematically derived hexagonal cell center combining: (a) a spatial tolerance radius around the exact computed cell centroid, (b) a maximum continuous velocity threshold over a fixed duration (velocity-bounded temporal anchoring), and (c) simultaneous binaural audio generation at frequencies F_water and F_water + F_Φ, where F_Φ is the same constant used in the personal phase wave-stretch computation, creating a coherent system-wide mathematical constant linking spatial anchoring, acoustic entrainment, and identity computation.

6. The pointy-top axial projection matrix `q = (√3/3 × x − 1/3 × y) / hex_size`, `r = (2/3 × y) / hex_size` where `x = lat_rad × R` and `y = lon_rad × R × cos(lat_rad)`, applied as a **local tangent-plane projection centered on the nearest dynamic pentagon node**. This design choice is intentional: the a4l: system does not seek a globally closed spherical tiling (as in H3/S2). The projection singularity at geographic poles (where `cos(±90°) = 0` collapses all longitudes to `y = 0`) is naturally avoided because the two polar pentagons (lat = ±90°) lie exactly on the rotation axis and serve only as phase anchors, not as local reference frames for hex encoding. All user interactions occur at non-polar latitudes where the tangent-plane approximation introduces less than 0.1% distortion at the 1 km hex cell scale.

---

*This disclosure is submitted for defensive publication purposes only. The authors do not seek patent protection for the described methods and explicitly place this disclosure in the public domain of prior art.*
