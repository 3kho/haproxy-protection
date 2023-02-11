function updateElem(selector, text) {
	document.querySelector(selector)
		.innerText = text;
}

function insertError(str) {
	const ring = document.querySelector('.lds-ring');
	const captcha = document.querySelector('#captcha');
	(ring || captcha).insertAdjacentHTML('afterend', `<p class="red">Error: ${str}</p>`);
	ring && ring.remove();
	captcha && captcha.remove();
	updateElem('.powstatus', '');
}

function finishRedirect() {
	window.location=location.search.slice(1)+location.hash || "/";
}

const wasmSupported = (() => {
    try {
        if (typeof WebAssembly === "object"
            && typeof WebAssembly.instantiate === "function") {
            const module = new WebAssembly.Module(Uint8Array.of(0x0, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00));
            if (module instanceof WebAssembly.Module)
                return new WebAssembly.Instance(module) instanceof WebAssembly.Instance;
        }
    } catch (e) {
		console.error(e);
    }
    return false;
})();

function postResponse(powResponse, captchaResponse) {
	const body = {
		'pow_response': powResponse,
	};
	if (captchaResponse) {
		body['h-captcha-response'] = captchaResponse;
		body['g-recaptcha-response'] = captchaResponse;
	}
	fetch('/.basedflare/bot-check', {
		method: 'POST',
		headers: {
		  'Content-Type': 'application/x-www-form-urlencoded',
		},
		body: new URLSearchParams(body),
		redirect: 'manual',
	}).then(res => {
		const s = res.status;
		if (s >= 400 && s < 500) {
			return insertError('bad challenge response request.');
		} else if (s >= 500) {
			return insertError('server responded with error.');
		}
		window.localStorage.setItem('basedflare-redirect', Math.random());
		finishRedirect();
	}).catch(() => {
		insertError('failed to send challenge response.');
	});
}

const powFinished = new Promise(resolve => {

	const start = Date.now();
	const workers = [];
	let finished = false;
	const stopPow = () => {
		finished = true;
		const hasCaptcha = document.getElementById('captcha');
		updateElem('.powstatus', `Found proof-of-work solution.${!hasCaptcha?' Submitting...':''}`);
		workers.forEach(w => w.terminate());
	};
	const submitPow = (answer) => {
		window.localStorage.setItem('basedflare-pow-response', answer);
		stopPow();
		resolve({ answer });
	};

	window.addEventListener('DOMContentLoaded', async () => {

		const { time, kb, pow, diff } = document.querySelector('[data-pow]').dataset;
		window.addEventListener('storage', event => {
			if (event.key === 'basedflare-pow-response' && !finished) {
				console.log('Got answer', event.newValue, 'from storage event');
				stopPow();
				resolve({ answer: event.newValue, localStorage: true });
			} else if (event.key === 'basedflare-redirect') {
				console.log('Redirecting, solved in another tab');
				finishRedirect();
			}
		});

		if (!wasmSupported) {
			return insertError('browser does not support WebAssembly.');
		}
		const argonOpts = {
			time: time,
			mem: kb,
			hashLen: 32,
			parallelism: 1,
			type: argon2.ArgonType.Argon2id,
		};
		console.log('Got pow', pow, 'with difficulty', diff);
		const eHashes = Math.pow(16, Math.floor(diff/8)) * ((diff%8)*2);
		const diffString = '0'.repeat(Math.floor(diff/8));
		const [userkey, challenge] = pow.split("#");
		if (window.Worker) {
			const cpuThreads = window.navigator.hardwareConcurrency;
			const isTor = location.hostname.endsWith('.onion');
			/* Try to use all threads on tor, because tor limits threads for anti fingerprinting but this
			   makes it awfully slow because workerThreads will always be = 1 */
			const workerThreads = isTor ? cpuThreads : Math.max(Math.ceil(cpuThreads/2),cpuThreads-1);
			const messageHandler = (e) => {
				if (e.data.length === 1) {
					const totalHashes = e.data[0]; //assumes all worker threads are same speed
					const elapsedSec = Math.floor((Date.now()-start)/1000);
					const hps = Math.floor(totalHashes/elapsedSec);
					const requiredSec = Math.floor(eHashes/hps) * 1.5; //estimate 1.5x time
					const remainingSec = Math.max(0, Math.floor(requiredSec-elapsedSec)); //dont show negative time
					return updateElem('.powstatus', `Proof-of-work: ${hps}H/s, ~${remainingSec}s remaining`);
				}
				if (finished) { return; }
				const [workerId, answer] = e.data;
				console.log('Worker', workerId, 'returned answer', answer, 'in', Date.now()-start+'ms');
				submitPow(`${pow}#${answer}`);
			}
			for (let i = 0; i < workerThreads; i++) {
				const argonWorker = new Worker('/.basedflare/js/worker.js');
				argonWorker.onmessage = messageHandler;
				workers.push(argonWorker);
			}
			for (let i = 0; i < workerThreads; i++) {
				await new Promise(res => setTimeout(res, 10));
				workers[i].postMessage([userkey, challenge, diff, diffString, argonOpts, i, workerThreads]);
			}
		} else {
			//TODO: remove this section, it _will_ cause problems
			console.warn('No webworker support, running in main/UI thread!');
			let i = 0;
			const start = Date.now();
			while(true) {
				const hash = await argon2.hash({
					pass: challenge + i.toString(),
					salt: userkey,
					...argonOpts,
				});
				if (hash.hashHex.startsWith(diffString)
					&& ((parseInt(hash.hashHex[diffString.length],16) &
						0xff >> (((diffString.length+1)*8)-diff)) === 0)) {
					console.log('Main thread found solution:', hash.hashHex, 'in', (Date.now()-start)+'ms');
					break;
				}
				++i;
			}
			submitPow(`${pow}#${i}`);
		}
	});
}).then((powResponse) => {
	const hasCaptchaForm = document.getElementById('captcha');
	if (!hasCaptchaForm && !powResponse.localStorage) {
		postResponse(powResponse.answer);
	}
	return powResponse.answer;
}).catch((e) => {
	console.error(e);
});

function onCaptchaSubmit(captchaResponse) {
	const captchaElem = document.querySelector('[data-sitekey]');
	captchaElem.insertAdjacentHTML('afterend', `<div class="lds-ring"><div></div><div></div><div></div><div></div></div>`);
	captchaElem.remove();
	powFinished.then(powResponse => {
		postResponse(powResponse, captchaResponse);
	});
}

