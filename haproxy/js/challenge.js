function finishRedirect() {
	window.location=location.search.slice(1)+location.hash || "/";
}

function postResponse(powResponse, captchaResponse) {
	const body = {
		'pow_response': powResponse,
	};
	if (captchaResponse) {
		body['h-captcha-response'] = captchaResponse;
		body['g-recaptcha-response'] = captchaResponse;
	}
	fetch('/bot-check', {
		method: 'POST',
		headers: {
		  'Content-Type': 'application/x-www-form-urlencoded',
		},
		body: new URLSearchParams(body),
		redirect: 'manual',
	}).then(res => {
		finishRedirect();
	})
}

const powFinished = new Promise((resolve, reject) => {
	window.addEventListener('DOMContentLoaded', (event) => {
		const combined = document.querySelector('[data-pow]').dataset.pow;
		const [userkey, challenge, signature] = combined.split("#");
		const start = Date.now();
		if (window.Worker && crypto.subtle) {
			const threads = Math.min(2,Math.ceil(window.navigator.hardwareConcurrency/2));
			let finished = false;
			const messageHandler = (e) => {
				if (finished) { return; }
				finished = true;
				workers.forEach(w => w.terminate());
				const [workerId, answer] = e.data;
				console.log('Worker', workerId, 'returned answer', answer, 'in', Date.now()-start+'ms');
				const dummyTime = 5000 - (Date.now()-start);
				window.setTimeout(() => {
					resolve(`${combined}#${answer}`);
				}, dummyTime);
			}
			const workers = [];
			for (let i = 0; i < threads; i++) {
				const shaWorker = new Worker('/js/worker.js');
				shaWorker.onmessage = messageHandler;
				workers.push(shaWorker);
			}
			workers.forEach((w, i) => w.postMessage([challenge, i, threads]));
		} else {
			console.warn('No webworker or crypto.subtle support, using legacy method in main/UI thread!');
			function sha256(ascii){function rightRotate(value,amount){return(value>>>amount)|(value<<(32-amount))};var mathPow=Math.pow;var maxWord=mathPow(2,32);var lengthProperty='length';var i,j;var result='';var words=[];var asciiBitLength=ascii[lengthProperty]*8;var hash=sha256.h=sha256.h||[];var k=sha256.k=sha256.k||[];var primeCounter=k[lengthProperty];var isComposite={};for(var candidate=2;primeCounter<64;candidate+=1){if(!isComposite[candidate]){for(i=0;i<313;i+=candidate){isComposite[i]=candidate}hash[primeCounter]=(mathPow(candidate,.5)*maxWord)|0;k[primeCounter++]=(mathPow(candidate,1/3)*maxWord)|0}}ascii+='\x80';while(ascii[lengthProperty]%64-56){ascii+='\x00';}for(i=0;i<ascii[lengthProperty];i+=1){j=ascii.charCodeAt(i);if(j>>8){return;}words[i>>2]|=j<<((3-i)%4)*8}words[words[lengthProperty]]=((asciiBitLength/maxWord)|0);words[words[lengthProperty]]=(asciiBitLength);for(j=0;j<words[lengthProperty];){var w=words.slice(j,j+=16);var oldHash=hash;hash=hash.slice(0,8);for(i=0;i<64;i+=1){var i2=i+j;var w15=w[i-15],w2=w[i-2];var a=hash[0],e=hash[4];var temp1=hash[7]+(rightRotate(e,6)^rightRotate(e,11)^rightRotate(e,25))+((e&hash[5])^((~e)&hash[6]))+k[i]+(w[i]=(i<16)?w[i]:(w[i-16]+(rightRotate(w15,7)^rightRotate(w15,18)^(w15>>>3))+w[i-7]+(rightRotate(w2,17)^rightRotate(w2,19)^(w2>>>10)))|0);var temp2=(rightRotate(a,2)^rightRotate(a,13)^rightRotate(a,22))+((a&hash[1])^(a&hash[2])^(hash[1]&hash[2]));hash=[(temp1+temp2)|0].concat(hash);hash[4]=(hash[4]+temp1)|0}for(i=0;i<8;i+=1){hash[i]=(hash[i]+oldHash[i])|0}}for(i=0;i<8;i+=1){for(j=3;j+1;j-=1){var b=(hash[i]>>(j*8))&255;result+=((b<16)?0:'')+b.toString(16)}}return result}
			const challengeIndex = parseInt(challenge[0], 16)*2;
			let i = 0
				, result;
			while(true) {
				result = sha256(challenge+i);
				if (result.substring(challengeIndex, challengeIndex+4) === '0041'){
					console.log('Main thread found solution:', i, result);
					break;
				}
				++i;
			}
			const dummyTime = 5000 - (Date.now()-start);
			window.setTimeout(() => {
				resolve(`${combined}#${i}`);
			}, dummyTime);
		}
	});
}).then((powResponse) => {
	const hasCaptchaForm = document.getElementById('captcha');
	if (!hasCaptchaForm) {
		postResponse(powResponse);
	}
	return powResponse;
});

function onCaptchaSubmit(captchaResponse) {
	const captchaElem = document.querySelector('[data-sitekey]');
	captchaElem.insertAdjacentHTML('afterend', `<div class="lds-ring"><div></div><div></div><div></div><div></div></div>`);
	captchaElem.remove();
	powFinished.then((powResponse) => {
		postResponse(powResponse, captchaResponse);
	});
}

