namespace Celeste.Mod.AurorasLoennPlugin {
    public class AurorasLoennPluginModuleSettings : EverestModuleSettings {

        public bool Enabled { get; set; } = true;
        [SettingSubText("aurorasloennplugin_modsettings_loennoverride")]
        public bool DoNotCheckForLoenn { get; set; } = false;
        [SettingRange(1, 20)]
        public int PlayerSamplingRate { get; set; } = 5;
        [SettingRange(1, 20)]
        public int HoldableSamplingRate { get; set; } = 15; 
        public bool PlayerSampledWithHoldableIfHolding { get; set; } = true;
    }
}
