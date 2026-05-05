{
  summarize = {
    tool = "summarize";
    description = "Summarize URLs, PDFs, YouTube videos";
    linux = true;
  };

  discrawl = {
    tool = "discrawl";
    description = "Archive and search Discord history";
    linux = true;
  };

  wacrawl = {
    tool = "wacrawl";
    description = "Archive and search WhatsApp Desktop history";
    linux = true;
  };

  peekaboo = {
    tool = "peekaboo";
    description = "Screenshot your screen";
    linux = false;
  };

  poltergeist = {
    tool = "poltergeist";
    description = "File watching and automation";
    linux = false;
  };

  sag = {
    tool = "sag";
    description = "Text-to-speech";
    linux = true;
  };

  camsnap = {
    tool = "camsnap";
    description = "Take photos from connected cameras";
    linux = true;
  };

  gogcli = {
    tool = "gogcli";
    description = "Google Calendar integration";
    linux = true;
  };

  goplaces = {
    tool = "goplaces";
    description = "Google Places API (New) CLI";
    defaultEnable = true;
    linux = true;
  };

  sonoscli = {
    tool = "sonoscli";
    description = "Control Sonos speakers";
    linux = true;
  };

  imsg = {
    tool = "imsg";
    description = "Send/read iMessages";
    linux = false;
  };
}
