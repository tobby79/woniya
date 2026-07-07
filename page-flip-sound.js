// 페이지/카드 넘김 클릭 효과음 공용 모듈. 각 템플릿은 DOM을 직접 다루지 않고
// 자기 클릭 핸들러에서 WoniyaSound.playFlip()을 호출해 연동한다.
window.WoniyaSound = (function(){
  var STORAGE_KEY = 'woniya_sound_muted';
  var AUDIO_SRC = 'audio/page-flip.mp3';
  var audio = null;
  var stored = null;
  try { stored = localStorage.getItem(STORAGE_KEY); } catch(e){}
  var muted = (stored === '1');
  var listeners = [];

  function ensureAudio(){
    if (audio) return audio;
    audio = new Audio(AUDIO_SRC);
    audio.preload = 'auto';
    return audio;
  }

  function isMuted(){ return muted; }

  function setMuted(next){
    muted = !!next;
    try { localStorage.setItem(STORAGE_KEY, muted ? '1' : '0'); } catch(e){}
    listeners.forEach(function(fn){ try { fn(muted); } catch(e){} });
  }

  function onMuteChange(fn){
    if (typeof fn === 'function') listeners.push(fn);
  }

  function playFlip(){
    if (muted) return;
    try {
      var el = ensureAudio();
      el.currentTime = 0;
      var p = el.play();
      if (p && p.catch) p.catch(function(){ /* 자동재생 차단 등은 조용히 무시 */ });
    } catch(e){ /* 조용히 무시 */ }
  }

  return { playFlip: playFlip, isMuted: isMuted, setMuted: setMuted, onMuteChange: onMuteChange };
})();
