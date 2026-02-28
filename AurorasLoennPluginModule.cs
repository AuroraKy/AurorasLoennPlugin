using Microsoft.Xna.Framework;
using Monocle;
using System.Linq;
using System.Collections.Generic;
using System.Net;
using System.IO;
using System.Reflection;
using MonoMod.RuntimeDetour;
using MonoMod.ModInterop;
using System.Runtime.CompilerServices;
using Color = Microsoft.Xna.Framework.Color;
using System;
using Image = Monocle.Image;
using System.Collections.Specialized;
using System.Text.RegularExpressions;
using System.Runtime.InteropServices;

[assembly: IgnoresAccessChecksTo("Celeste")]
namespace Celeste.Mod.AurorasLoennPlugin {
    public class AurorasLoennPluginModule : EverestModule {
        public static AurorasLoennPluginModule Instance { get; private set; }

        public override Type SettingsType => typeof(AurorasLoennPluginModuleSettings);
        public static AurorasLoennPluginModuleSettings Settings => (AurorasLoennPluginModuleSettings) Instance._Settings;

        public static bool LOENN_IS_OPEN = true;
        // if debugrc is not active we write to files.
        public static bool DEBUGRC_ACTIVE = false;
        public static DateTime lastDebugRCTime = DateTime.MinValue;

        private List<PlayerState> PlayerPath;
        private readonly HashSet<PlayerState> PlayerStates = new(new StateComparer());
        private List<HoldableState> HoldablePath; // all combined
        private readonly HashSet<HoldableState> HoldableStates = new(new StateComparer());
        private int lastRequestedIDPlayer = -1; // -1 stands for return full, indicated in the debugrc
        private int lastRequestedIDHoldable = -1;

        private bool playerDied;
        private int counter = 0;
        public static int stateCounter = 1;

        //private Dictionary<Holdable, HoldableState> lastHoldableState;

        private const string TOP_FOLDER = "ModFiles";
        private const string MOD_FOLDER = "aurora_aquir_AurorasLoennPlugin";
        private bool ChangesMade = false;

        private Vector2 MadelineRespawnPosition = new Vector2();
        private bool MadelineRespawned = false; // this is JustRespawned but me doing it manually cause of savestates

        class StateComparer : IEqualityComparer<PlayerState>, IEqualityComparer<HoldableState>
        {
            public StateComparer()
            {

            }
            public bool Equals(PlayerState x, PlayerState y)
            {
                return x.roomName == y.roomName && x.x == y.x && x.y == y.y && x.color == y.color && x.flipX == y.flipX && x.flipY == y.flipY;
            }

            public bool Equals(HoldableState x, HoldableState y)
            {
                return x.roomName == y.roomName && x.x == y.x && x.y == y.y && x.sprite == y.sprite && x.flipX == y.flipX && x.flipY == y.flipY;
            }

            public int GetHashCode(PlayerState obj)
            {
                return obj.roomName.GetHashCode() ^ obj.x.GetHashCode() ^ obj.y.GetHashCode() ^ obj.color.GetHashCode() ^ obj.flipX.GetHashCode() ^ obj.flipY.GetHashCode();
            }

            public int GetHashCode(HoldableState obj)
            {
                return obj.roomName.GetHashCode() ^ obj.x.GetHashCode() ^ obj.y.GetHashCode() ^ obj.sprite.GetHashCode() ^ obj.flipX.GetHashCode() ^ obj.flipY.GetHashCode();
            }
        }

        class PlayerState
        {
            public readonly int id;
            public readonly float x;
            public readonly float y;
            public readonly Color color;
            public readonly bool flipX;
            public readonly bool flipY;
            public readonly string roomName;
            public readonly bool ducking;

            public PlayerState(Player player, float xOffset, float yOffset, string roomName)
            {
                this.id = stateCounter + 1;
                stateCounter = id;
                this.x = player.Position.X - xOffset;
                this.y = player.Position.Y - yOffset;
                Color? overrideHairColor = player?.OverrideHairColor;
                Color hairColor = (overrideHairColor ?? player?.Hair?.GetHairColor(0)) ?? player.Hair.Color;
                this.color = hairColor;
                this.flipX = player.Facing == Facings.Left;
                this.flipY = (GravityHelperExports.GetPlayerGravity?.Invoke() ?? 0) != 0;
                this.roomName = Regex.Replace(roomName, "[^a-zA-Z0-9 ]", "_");
                this.ducking = player.Ducking;
            }

            public override string ToString()
            {
                string colorHex = color.R.ToString("X2") + color.G.ToString("X2") + color.B.ToString("X2");
                return $"{id},{roomName},{x},{y},{colorHex},{flipX},{flipY},{ducking}";
            }

        }

        class HoldableState
        {
            public readonly int id;
            public readonly float x;
            public readonly float y;
            public readonly bool flipX;
            public readonly bool flipY;
            public readonly string sprite;
            public readonly string roomName;

            public HoldableState(Holdable holdable, float xOffset, float yOffset, string sprite, string roomName)
            {
                this.id = stateCounter + 1;
                stateCounter = id;
                this.flipX = false;
                this.flipY = (GravityHelperExports.GetActorGravity?.Invoke(holdable.Entity as Actor) ?? 0) != 0;
                this.x = holdable.Entity.Position.X - xOffset;
                this.y = holdable.Entity.Position.Y - yOffset + this.handleVanillaYOffset(holdable);
                this.sprite = sprite;
                this.roomName = Regex.Replace(roomName, "[^a-zA-Z0-9 ]", "_");
            }

            private int handleVanillaYOffset(Holdable holdable)
            {
                if (holdable.Entity == null) return 0;
                //if (holdable.Entity is TheoCrystal) return 1; // not correct after all
                if (holdable.Entity.GetType().ToString() == "Celeste.Mod.VortexHelper.Entities.BowlPuffer")
                {
                    if (flipY) return -8 * 3 + 1;
                    else return 8 * 3 - 1;
                }
                if (holdable.Entity.GetType().ToString() == "Celeste.Mod.CommunalHelper.Entities.DreamJellyfish")
                {
                    if (flipY) return -8*8 + 2;
                    else return 8*8 - 2;
                }
                if (holdable.Entity is Glider) // this is because the glider sprite is huge.
                {
                    if (flipY) return -8;
                    else return 8;
                }
                return 0;
            }

            public override string ToString()
            {
                return $"{id},{roomName},{x},{y},{sprite},{flipX},{flipY}";
            }
        }

        private List<RCEndPoint> RCEndPoints = new List<RCEndPoint>();
        public AurorasLoennPluginModule() {
            Instance = this;
            PlayerPath = new List<PlayerState>();
            HoldablePath = new List<HoldableState>();
            playerDied = false; 
        }

        [ModImportName("GravityHelper")]
        public static class GravityHelperExports
        {
            public static Func<int> GetPlayerGravity;
            public static Func<Actor, int> GetActorGravity;
            //(int)(actor?.GetGravity() ?? GravityType.Normal);

        }
        [ModImportName("SpeedrunTool.SaveLoad")]
        public static class SpeedrunToolImports {
            public static Func<Action<Dictionary<Type, Dictionary<string, object>>, Level>, Action<Dictionary<Type, Dictionary<string, object>>, Level>, Action, Action<Level>, Action<Level>, Action, object> RegisterSaveLoadAction;
            public static Action<object> Unregister;
        }

        private static object SavestateAction;

        public override void Load()
        {
            typeof(GravityHelperExports).ModInterop();
            typeof(SpeedrunToolImports).ModInterop();

            SavestateAction = SpeedrunToolImports.RegisterSaveLoadAction?.Invoke(null, OnLoadState, null, null, null, null);

            On.Celeste.Level.Update += ModLevelUpdate;
            Everest.Events.Player.OnDie += OnPlayerDeath;

            RCEndPoints.Add(new RCEndPoint
            {
                Path = "/aurora_aquir/PlayerStatePath",
                PathHelp = "/aurora_aquir/PlayerStatePath?partial={true|false}",
                Name = "Player State Path",
                InfoHTML = "Returns the Player Path since last death. id, roomName, x, y, colorHex, flipX, flipY",
                Handle = delegate (HttpListenerContext c)
                {
                    lastDebugRCTime = DateTime.Now;
                    NameValueCollection nameValueCollection = Everest.DebugRC.ParseQueryString(c.Request.RawUrl);

                    if (nameValueCollection["partial"] != "true")
                    {
                        // give back all of it 
                        Everest.DebugRC.Write(c, GetPlayerString(false));
                    } else
                    {
                        // give back only the "new" things since last call
                        Everest.DebugRC.Write(c, GetPlayerString(true));
                    }
                }
            });

            RCEndPoints.Add(new RCEndPoint
            {
                Path = "/aurora_aquir/HoldableStatePath",
                PathHelp = "/aurora_aquir/PlayerStatePath?partial={true|false}",
                Name = "Holdable State Path",
                InfoHTML = "Returns all Holdable Paths since last death. id, roomName, x,y, sprite, flipX, flipY",
                Handle = delegate (HttpListenerContext c)
                {
                    lastDebugRCTime = DateTime.Now;
                    NameValueCollection nameValueCollection = Everest.DebugRC.ParseQueryString(c.Request.RawUrl);

                    if (nameValueCollection["partial"] != "true")
                    {
                        Everest.DebugRC.Write(c, GetHoldableString(false));
                    }
                    else
                    {
                        Everest.DebugRC.Write(c, GetHoldableString(true));
                    }
                }
            });

            RCEndPoints.Add(new RCEndPoint {
                Path = "/aurora_aquir/ClearPaths",
                Name = "Clears all paths",
                InfoHTML = "This is used by Aurora's Lönn Plugin to clear all paths when Clear Paths is pressed.",
                Handle = delegate (HttpListenerContext c) {
                    lastDebugRCTime = DateTime.Now;

                    ClearPaths();

                    Everest.DebugRC.Write(c, "OK");
                }
            });

            RCEndPoints.Add(new RCEndPoint
            {
                Path = "/aurora_aquir/LoennIsOpen",
                Name = "Loenn is Open",
                InfoHTML = "This is used by Aurora's Lönn Plugin to notify the c# code that loenn is open and debugrc works.",
                Handle = delegate (HttpListenerContext c)
                {
                    lastDebugRCTime = DateTime.Now;
                    DEBUGRC_ACTIVE = true;
                    LOENN_IS_OPEN = true;
                    Everest.DebugRC.Write(c, "OK");
                }
            });

            foreach(RCEndPoint rcEndPoint in RCEndPoints)
            {
                Everest.DebugRC.EndPoints.Add(rcEndPoint);
            }

            Settings.DoNotCheckForLoenn = false;

        }


        [Command("aurorasloennplugin_debug", "Information about aurora's loenn plugin meant for debug")]
        public static void DebugInfo()
        {
            Engine.Commands.Log($"---- Aurora's Loenn Plugin\n" +
                $"Last DebugRC ping from Loenn: {lastDebugRCTime}\n" +
                $"DebugRC Active: {DEBUGRC_ACTIVE}\n" +
                $"Loenn is open: {LOENN_IS_OPEN}\n" +
                $"Checking for Loenn? {(Settings.DoNotCheckForLoenn ? "No" : "Yes")}");
        }
         

        public override void Unload()
        {
            On.Celeste.Level.Update -= ModLevelUpdate;
            Everest.Events.Player.OnDie -= OnPlayerDeath;

            SpeedrunToolImports.Unregister?.Invoke(SavestateAction);

            foreach (RCEndPoint rcEndPoint in RCEndPoints)
            {
                Everest.DebugRC.EndPoints.Remove(rcEndPoint);
            }

            ClearPaths();
        }

        private string GetPlayerString(bool partial = false)
        {
            string ret = "0";
            bool wasReset = lastRequestedIDPlayer < 0;
            foreach (PlayerState state in PlayerPath.ToArray())
            {
                if(!partial || state.id > lastRequestedIDPlayer)
                {
                    ret += state.ToString() + "\n";
                    if (partial) lastRequestedIDPlayer = state.id;
                }
            }

            ret = $"{ret.Count(c => c == '\n')},{partial && !wasReset}\n{ret}";
            return ret;
        }

        private string GetHoldableString(bool partial = false)
        {

            string ret = "0";
            bool wasReset = lastRequestedIDHoldable < 0;
            foreach (HoldableState state in HoldablePath.ToArray())
            {
                if (!partial || state.id > lastRequestedIDHoldable)
                {
                    ret += state.ToString() + "\n";
                    if (partial) lastRequestedIDHoldable = state.id;
                }
            }

            ret = $"{ret.Count(c => c == '\n')},{partial && !wasReset}\n{ret}";
            return ret;
        }

        private void OnPlayerDeath(Player obj)
        {
            if (!Settings.Enabled) return;
            counter = -5; // at least 5 frames of leniency
            MadelineRespawned = true;
        }


        private static void OnLoadState(Dictionary<Type, Dictionary<string, object>> dictionary, Level level)
        {
            if(Settings.ResetPathOnState) {
                Instance.ClearPaths();
            }
        }

        private void ClearPaths()
        {
            MadelineRespawnPosition = Vector2.Zero;
            PlayerStates.Clear();
            HoldableStates.Clear();

            PlayerPath.Clear();
            HoldablePath.Clear();
            lastRequestedIDPlayer = -1;
            lastRequestedIDHoldable = -1;
            stateCounter = 1;
            ensureDirectory();
            using StreamWriter writerP = File.CreateText(Path.Combine(Everest.PathGame, TOP_FOLDER, MOD_FOLDER, $"PlayerStatePath.txt"));
            writerP.WriteLine("0");

            using StreamWriter writerH = File.CreateText(Path.Combine(Everest.PathGame, TOP_FOLDER, MOD_FOLDER, $"HoldableStatePath.txt"));
            writerH.WriteLine("0");

        }

        private void ensureDirectory()
        {
            Directory.CreateDirectory(Path.Combine(Everest.PathGame, TOP_FOLDER));
            Directory.CreateDirectory(Path.Combine(Everest.PathGame, TOP_FOLDER, MOD_FOLDER));
        }

        private void WriteFiles()
        {
            ensureDirectory();
            using StreamWriter writerP = File.CreateText(Path.Combine(Everest.PathGame, TOP_FOLDER, MOD_FOLDER, $"PlayerStatePath.txt"));
            writerP.WriteLine(GetPlayerString());

            using StreamWriter writerH = File.CreateText(Path.Combine(Everest.PathGame, TOP_FOLDER, MOD_FOLDER, $"HoldableStatePath.txt"));
            writerH.WriteLine(GetHoldableString());

            ChangesMade = false;
        }

        private void CollectHoldableData(Level level)
        {
            if (level == null) return;

            //if (HoldablePath == null) HoldablePath = new List<HoldableState>();

            List<Component> holdables = level.Tracker.GetComponents<Holdable>();

            foreach(Holdable holdable in holdables)
            {
                if (holdable == null || holdable.Entity == null) continue;
                if (holdable.Entity is Glider glider && glider.bubble) continue;
                if (!level.IsInBounds(holdable.Entity.Position, 5f)) continue;

                string TexturePath;
                Sprite sprite = holdable.Entity?.Components?.Get<Sprite>();
                if (sprite == null)
                {
                    Image image = holdable.Entity?.Components?.Get<Image>();
                    if (image == null) return;
                    TexturePath = image.Texture.ToString();
                } else
                {
                    TexturePath = sprite.Texture.ToString();
                }
                if (TexturePath == null) return;
                HoldableState state = new(holdable, level.LevelOffset.X, level.LevelOffset.Y, TexturePath, level.Session.Level);
                if (!HoldableStates.Contains(state))// (!lastHoldableState.TryGetValue(holdable, out HoldableState lastState) || !lastState.Equals(state)))
                {
                    //lastHoldableState[holdable] = state;
                    HoldableStates.Add(state);
                    HoldablePath.Add(state);
                    ChangesMade = true;
                } else
                {
                    stateCounter--;
                }
            }

        }

        private void CollectPlayerData(Level level)
        {
            if (PlayerPath == null) PlayerPath = new List<PlayerState>();

            Player player = level?.Tracker?.GetEntity<Player>();

            if (player != null && level != null && level.Session != null)
            {
                if (player.JustRespawned) MadelineRespawnPosition = player.Position; // if just respawned works use it lol 
                if (MadelineRespawned && player.Position == MadelineRespawnPosition)
                {
                    playerDied = true;
                    return;
                }
                if (playerDied) {
                    playerDied = false;
                    MadelineRespawned = false;
                    ClearPaths();
                }

                PlayerState state = new(player, level.LevelOffset.X, level.LevelOffset.Y, level.Session.Level);
                //PlayerState lastState = PlayerPath.LastOrDefault();

                if (!PlayerStates.Contains(state)) //lastState == null || !lastState.Equals(state))
                {
                    PlayerStates.Add(state);
                    PlayerPath.Add(state);
                    ChangesMade = true;
                }
                else
                {
                    stateCounter--;
                }
            }
        }

        private void ModLevelUpdate(On.Celeste.Level.orig_Update orig, Level self)
        {
            orig(self);
            if(!Settings.Enabled) return;
            if (Engine.Scene.OnInterval(1f) && ChangesMade && !DEBUGRC_ACTIVE)
            {
                WriteFiles();
            }

            // Every 15s check if debugrc works, if not check if loenn exists (file ver)
            if (Engine.Scene.OnInterval(15f))
            {
                if (!Settings.DoNotCheckForLoenn && !DEBUGRC_ACTIVE)
                {
                    string path = Path.Combine(Everest.PathGame, TOP_FOLDER, MOD_FOLDER, $"loennOpen");
                    if (File.Exists(path) && File.GetLastWriteTime(path) > DateTime.Now.AddSeconds(-30))
                    {
                        if (!LOENN_IS_OPEN) Logger.Log(LogLevel.Info, "Aurora's Loenn Plugin", "Confirmed Loenn is open using files, writing path files until debugrc is called again");
                        LOENN_IS_OPEN = true;
                    }
                    else
                    {
                        if (LOENN_IS_OPEN) Logger.Log(LogLevel.Info, "Aurora's Loenn Plugin", "Cannot confirm Loenn is open, no longer collecting data.");
                        LOENN_IS_OPEN = false;
                    }
                } else if (lastDebugRCTime < DateTime.Now.AddSeconds(-15))
                {
                    DEBUGRC_ACTIVE = false;
                }
            }

            if (!Settings.DoNotCheckForLoenn && !LOENN_IS_OPEN) return;

            counter++;

            int playerSample = counter % Settings.PlayerSamplingRate;
            int holdableSample = counter % Settings.HoldableSamplingRate;

            if(playerSample == 0 && holdableSample == 0)
            {
                counter = 0;
            } else if (playerSample != 0 && holdableSample != 0)
            {
                return;
            }

            if (PlayerPath == null) PlayerPath = new();

            Player player = self?.Tracker?.GetEntity<Player>();
            // If player is holding only sample on holdable sample rate.
            if(player != null && player.Holding != null && Settings.PlayerSampledWithHoldableIfHolding)
            {
                playerSample = 1;
            }
            if (holdableSample == 0)
            {
                CollectHoldableData(self);
            }
            if (playerSample == 0 || (Settings.PlayerSampledWithHoldableIfHolding && holdableSample == 0))
            {
                CollectPlayerData(self);
            }
        }

    }
}