import os
import sys
import spotipy
from spotipy.oauth2 import SpotifyOAuth
from spotipy.exceptions import SpotifyOauthError
from dotenv import load_dotenv

load_dotenv()


def handle_expired_login(sp):
    """Spotify refresh tokens now expire ~6 months after authorization. When the
    token endpoint returns 400 invalid_grant, spotipy raises SpotifyOauthError.
    Clear the dead token and ask the user to re-run so a fresh browser login runs."""
    print("\n⚠️  Your Spotify login has expired (refresh tokens now expire ~6 months after authorization).")
    try:
        cache_path = sp.auth_manager.cache_handler.cache_path
        if os.path.exists(cache_path):
            os.remove(cache_path)
            print(f"Cleared the expired token ({cache_path}).")
    except Exception:
        pass
    print("Re-run this script to sign in again.")
    sys.exit(1)


sp = spotipy.Spotify(auth_manager=SpotifyOAuth(scope='playlist-read-private playlist-read-collaborative'))

# Get all user playlists
print("Fetching all playlists...")
try:
    results = sp.current_user_playlists(limit=50)
    playlists = results['items']
    while results['next']:
        results = sp.next(results)
        playlists.extend(results['items'])
except SpotifyOauthError:
    handle_expired_login(sp)

# Find the specific playlist
target_name = "A&R - Unsigned Male Rappers to Track [2026]"
print(f"\nLooking for: '{target_name}'")
print(f"Total playlists: {len(playlists)}")

found = False
for p in playlists:
    if target_name.lower() in p['name'].lower() or 'unsigned male rapper' in p['name'].lower():
        print(f"\nFound similar: '{p['name']}'")
        print(f"  ID: {p['id']}")
        if p['name'] == target_name:
            print("  ✓ EXACT MATCH!")
            found = True
        
if not found:
    print(f"\n❌ Exact match NOT found for '{target_name}'")
    print("\nAll A&R playlists:")
    ar_playlists = [p for p in playlists if 'A&R' in p['name']]
    for p in ar_playlists:
        print(f"  - {p['name']}")
