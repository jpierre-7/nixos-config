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
  };
}
