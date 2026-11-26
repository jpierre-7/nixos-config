{ pkgs, ... }:
{
  # PipeWire with its ALSA, PulseAudio and JACK front-ends, as on Arch.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true; # lets PipeWire use realtime scheduling
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;

    # The soundboard (pkgs/soundboard/, ported from HefKer/nixos-config):
    # sound-pick plays into soundboard-in, a sink whose loopback is the
    # "Soundboard mic" source, beside a cleaned-up copy of the default mic. Set
    # Vesktop's input device to it once. priority.session 0 keeps WirePlumber
    # from making either node the default.
    extraConfig.pipewire."90-soundboard"."context.modules" = [
      {
        name = "libpipewire-module-loopback";
        args = {
          "node.description" = "Soundboard mic";
          "capture.props" = {
            "node.name" = "soundboard-in";
            "media.class" = "Audio/Sink";
            "audio.position" = [
              "FL"
              "FR"
            ];
            "priority.session" = 0;
          };
          "playback.props" = {
            "node.name" = "soundboard-mic";
            "media.class" = "Audio/Source";
            "audio.position" = [
              "FL"
              "FR"
            ];
            "priority.session" = 0;
          };
        };
      }
      {
        # DeepFilterNet then gain on the mic alone, so Discord's noise filter
        # can be off and stop eating the sounds.
        name = "libpipewire-module-filter-chain";
        args = {
          "node.description" = "Mic into soundboard";
          "media.name" = "Mic into soundboard";
          "filter.graph" = {
            nodes = [
              {
                type = "ladspa";
                name = "denoise";
                plugin = "${pkgs.deepfilternet}/lib/ladspa/libdeep_filter_ladspa.so";
                label = "deep_filter_mono";
                # How far noise is pushed down; 100 removes it outright, lower sounds more natural.
                control."Attenuation Limit (dB)" = 100.0;
              }
              {
                type = "builtin";
                name = "gain";
                label = "linear";
                # Output = input x Mult; 4.0 is +12 dB, HefKer's value for their
                # mic. Lower it if friends hear you too loud.
                control.Mult = 4.0;
              }
            ];
            links = [
              {
                output = "denoise:Audio Out";
                input = "gain:In";
              }
            ];
          };
          # Passive, so the real mic stays suspended until something records the soundboard mic.
          "capture.props" = {
            "audio.rate" = 48000;
            "node.name" = "soundboard-pass";
            "node.passive" = true;
            "stream.capture.sink" = false;
          };
          "playback.props" = {
            "node.name" = "soundboard-pass.out";
            "node.passive" = true;
            "audio.rate" = 48000;
            "target.object" = "soundboard-in";
            "node.dont-reconnect" = true;
          };
        };
      }
    ];
  };
}
