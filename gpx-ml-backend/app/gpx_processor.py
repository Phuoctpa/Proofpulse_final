import gpxpy

def extract_features_from_gpx(gpx_path):
    print(f"[DEBUG] Reading GPX file from path: {gpx_path}")
    with open(gpx_path, 'r') as f:
        gpx = gpxpy.parse(f)
        for track in gpx.tracks:
            print(f"[DEBUG] Processing track: {track.name}")
            for segment in track.segments:
                points = segment.points
                print(f"[DEBUG] Number of points in segment: {len(points)}")

                if len(points) < 2:
                    print("[ERROR] Not enough points to calculate features.")
                    return None

                start_time = points[0].time
                end_time = points[-1].time
                duration = (end_time - start_time).total_seconds() / 60
                distance = sum(points[i-1].distance_3d(points[i]) for i in range(1, len(points))) / 1000
                speed = distance / (duration / 60) if duration > 0 else 0
                elevation = sum(
                    max(points[i].elevation - points[i-1].elevation, 0)
                    for i in range(1, len(points))
                )

                features = {
                    'total_distance_km': round(distance, 2),
                    'duration_minutes': round(duration, 2),
                    'avg_speed_kmh': round(speed, 2),
                    'elevation_gain_m': round(elevation, 2),
                    'activity_timestamp': int(end_time.timestamp())  # thêm timestamp
                }
                print(f"[DEBUG] Extracted features: {features}")
                return features

    print("[ERROR] No track/segment found in GPX file.")
    return None
